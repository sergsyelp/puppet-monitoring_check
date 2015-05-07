#!/opt/sensu/embedded/bin/ruby

$: << File.dirname(__FILE__)

require 'socket'
require 'net/http'
require 'tiny_redis'

if !defined?(IN_RSPEC)
  require 'rubygems'
  require 'sensu'
  require 'sensu/constants' # version is here
  require 'sensu/settings'
  require 'sensu-plugin/check/cli'
  require 'json'
end

class CheckCluster < Sensu::Plugin::Check::CLI
  option :cluster_name,
    :short => "-N NAME",
    :long => "--cluster-name NAME",
    :description => "Name of the cluster to use in the source of the alerts",
    :required => true

  option :check,
    :short => "-c CHECK",
    :long => "--check CHECK",
    :description => "Aggregate CHECK name",
    :required => true,
    :default => 80

  option :critical,
    :short => "-C PERCENT",
    :long => "--critical PERCENT",
    :description => "PERCENT non-ok before critical",
    :proc => proc {|a| a.to_i }

  option :silenced,
    :short => "-S yes",
    :long => "--silenced yes",
    :description => "Include silenced hosts in total",
    :default => false

  def run
    unless check_sensu_version
      unknown "Sensu <0.13 is not supported"
      return
    end

    lock_key         = "lock:#{config[:cluster_name]}:#{config[:check]}"
    cluster_interval = cluster_check[:interval] || 300
    mutex            = TinyRedis::Mutex.new(redis, lock_key, cluster_interval)
    expiration       = mutex.run_with_lock_or_skip do
      status, output = check_aggregate(
        aggregator.summary(target_check[:interval] || 300))
      logger.puts output
      send_payload EXIT_CODES[status], output
      ok "Check executed successfully (#{status}: #{output})"
      return
    end

    if !expiration
      # return in the block means we should never enter this branch
      unknown "Unknown lock problem"
    elsif expiration < 0
      critical "Lock #{distributed_mutex.key} is not set to expire"
    elsif expiration > cluster_interval
      critical("Lock #{lock_key} expiration #{expiration} " <<
        "exceeds check interval #{cluster_interval}")
    else
      ok "Did not run, locked for another #{expiration}s"
    end
  rescue RuntimeError => e
    critical "#{e.message} (#{e.class}): #{e.backtrace.inspect}"
  end

private

  def aggregator
    RedisCheckAggregate.new(redis, config[:check], [config[:cluster_name]])
  end

  def check_sensu_version
    # good enough
    Sensu::VERSION.split('.')[1].to_i > 12
  end

  EXIT_CODES = Sensu::Plugin::EXIT_CODES

  def logger
    $stdout
  end

  def redis
    @redis ||= begin
      redis_config = sensu_settings[:redis] or raise "Redis config not available"
      TinyRedis::Client.new(redis_config[:host], redis_config[:port])
    end
  end

  # accept summary:
  #   total:    all server that had ran the check in the past
  #   ok:       number of *active* servers with check status OK
  #   silenced: number of *total* servers that are silenced or have
  #             target check silenced
  def check_aggregate(summary)
    total, ok, silenced = summary.values_at(:total, :ok, :silenced)
    return 'OK', 'No servers running the check' if total.zero?

    eff_total = total - silenced * (config[:silenced] ? 1 : 0)
    return 'OK', 'All hosts silenced' if eff_total.zero?

    ok_pct  = (100 * ok / eff_total.to_f).to_i

    message = "#{ok} OK out of #{eff_total} total."
    message << " #{silenced} silenced." if config[:silenced] && silenced > 0
    message << " (#{ok_pct}% OK, #{config[:critical]}% threshold)"

    state = ok_pct >= config[:critical] ? 'OK' : 'CRITICAL'
    return state, message
  end

  def api
    @api ||= SensuApi.new(
      *sensu_settings[:api].values_at(:host, :port, :user, :password))
  end

  def sensu_settings
    @sensu_settings ||=
      Sensu::Settings.get(:config_dirs => ["/etc/sensu/conf.d"]) or
      raise "Sensu settings not available"
  end

  def send_payload(status, output)
    payload = target_check.merge(
      :status => status,
      :output => output,
      :source => config[:cluster_name],
      :name   => config[:check],
      :page   => cluster_check[:page],
      :team   => cluster_check[:team],
      :notification_email => cluster_check[:notification_email],
      :irc_channels       => cluster_check[:irc_channels])

    payload[:runbook] = cluster_check[:runbook] if cluster_check[:runbook] != '-'
    payload[:tip]     = cluster_check[:tip] if cluster_check[:tip] != '-'
    payload.delete :command

    sock = TCPSocket.new('localhost', 3030)
    sock.puts payload.to_json
    sock.close
  end

  def cluster_check
    return {} if ENV['DEBUG']
    return JSON.parse(ENV['DEBUG_CC']) if ENV['DEBUG_CC']

    sensu_settings[:checks][:"#{config[:cluster_name]}_#{config[:check]}"] or
      raise "#{config[:cluster_name]}_#{config[:check]} not found in sensu settings"
  end

  def target_check
    @target_check ||=
      sensu_settings[:checks][config[:check]] or
      api.request("/checks/#{config[:check]}") or
        raise "#{config[:check]} not found in sensu settings"
  end
end

class SensuApi
  attr_accessor :host, :port, :user, :password

  def initialize(host, port, user=nil, password=nil)
    @host = host
    @port = port
    @user = user
    @password = password
  end

  def request(path, opts={})
    uri = URI("http://#{host}:#{port}#{path}")
    uri.query = URI.encode_www_form(opts)

    req = Net::HTTP::Get.new(uri)
    req.basic_auth(user, password) if user && password

    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body, :symbolize_names => true)
    else
      raise "Error querying sensu api: #{res.code} '#{res.body}'"
    end
  end
end

class RedisCheckAggregate
  def initialize(redis, check, ignores=[])
    @check   = check
    @redis   = redis
    @ignores = ignores
  end

  def summary(interval)
    all     = last_execution find_servers
    active  = all.select { |_, time| time.to_i >= Time.now.to_i - interval }
    { :total    => all.size,
      :ok       => active.count do |server, _|
        @redis.lindex("history:#{server}:#@check", -1) == '0'
      end,
      :silenced => all.count do |server, time|
        %W{ stash:silence/#{server} stash:silence/#@check
            stash:silence/#{server}/#@check }.any? {|key| @redis.get(key) }
      end }
  end

  private

  # { server_name => timestamp, ... }
  def last_execution(servers)
    servers.inject({}) do |hash, server|
      hash[server] = @redis.get("execution:#{server}:#@check")
      hash
    end
  end

  def find_servers
    # TODO: reimplement using @redis.scan for webscale
    @servers ||= @redis.keys("execution:*:#@check").
      map {|key| key.split(':')[1]}.reject{|server| @ignores.include? server}
  end
end
