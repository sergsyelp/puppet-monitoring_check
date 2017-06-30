#!/opt/sensu/embedded/bin/ruby

$: << File.dirname(__FILE__)

#
# Check Cluster
#

require 'json'
require 'socket'
require 'net/http'
require 'logger'
require 'time'
require 'tiny_redis'

if !defined?(IN_RSPEC)
  require 'rubygems'
  require 'sensu'
  require 'sensu/constants' # version is here
  require 'sensu/settings'
  require 'sensu-plugin/check/cli'
end


class NoServersFound < RuntimeError
end


class CheckCluster < Sensu::Plugin::Check::CLI
  option :cluster_name,
    :short => "-N NAME",
    :long => "--cluster-name NAME",
    :description => "Name of the cluster to use in the source of the alerts",
    :required => true

  option :multi_cluster,
    :short => "-M yes",
    :long => "--multi-cluster yes",
    :description => "Group by cluster_name of client/child nodes.",
    :default => false

  option :min_nodes,
    :short => "-m MIN",
    :long => "--minimum-nodes MIN",
    :description => "The minimum number of nodes that should be available",
    :proc => proc {|a| a.to_i },
    :default => 0

  option :check,
    :short => "-c CHECK",
    :long => "--check CHECK",
    :description => "Aggregate CHECK name",
    :required => true

  option :pct_critical,
    :short => "-C PERCENT",
    :long => "--critical PERCENT",
    :description => "PERCENT minimum OK threshold (below this number, send alert)",
    :proc => proc {|a| a.to_i },
    :default => 80

  option :num_critical,
    :short => '-u NUM',
    :long => '--num-critical NUM',
    :description => 'NUMBER minimum OK threshold (below this number, send alert)',
    :proc => proc {|a| a.to_i },
    :required => false

  option :silenced,
    :short => "-S yes",
    :long => "--silenced yes",
    :description => "Include silenced hosts in total",
    :default => false

  option :ignore_nohosts,
    :short => "-I yes",
    :long => "--ignore-nohosts yes",
    :description => "Don't fail if there are no hosts",
    :default => false

  option :dryrun,
    :short => "-d",
    :long => "--dry-run",
    :description => "Run cluster check without any redis locking or sensu alerting",
    :default => false

  option :verbose,
    :short => "-v",
    :long => "--verbose",
    :description => "Print debug information",
    :default => false

  def run
    unless check_sensu_version
      unknown "Sensu <0.13 is not supported"
      return
    end

    if !cluster_check[:interval]
      critical "Please configure interval"
      return
    end
    if config[:multi_cluster]
      run_multi
    else
      run_single
    end
  end

  def aggregator
    raise_no_server_found = !(config[:multi_cluster] and config[:ignore_nohosts])
    RedisCheckAggregate.new( redis, config[:check], logger, config[:cluster_name], raise_no_server_found)
  end

private
 
  # multi_cluster is not enabled: do a single check across all nodes.
  # Sending cluster status (is cluster ok?) is delegated.
  # Check status (is check working?) is reported in this func.
  def run_single
    result = run_single_child
    code = EXIT_CODES[result[0].to_s.upcase]
    message = result[1]
    method_name = EXIT_CODES.key(code).downcase
    send(method_name, message)
  end

  # multi_cluster is enabled: do a cluster check for each child cluster.
  # Sending cluster status (is cluster ok?) is delegated.
  # Check status results (are checks working?) are collected and the worst ones
  # are combined and reported.
  def run_multi
    results = aggregator.child_cluster_names.map do |child_cluster_name|
      run_single_child(child_cluster_name)
    end 
    if results.empty?
      send('ok', 'No child clusters found in this sensu cluster.')
    else
      results_with_code = results.map do |result|
        [EXIT_CODES[result[0].to_s.upcase], result[1]]
      end 
      worst_code = results_with_code.map {|result| result[0]}.max
      message = results_with_code
          .select{|result| result[0]==worst_code}
          .map{|result| result[1]}
          .uniq
          .join(';')
      worst_method_name = EXIT_CODES.key(worst_code).downcase
      send(worst_method_name, message)
    end
  end

  # Returns check status, message (is check working?), for possible aggregation.
  # Sends cluster status payload (is the cluster ok?)
  def run_single_child(child_cluster_name=nil)
    lock_key = "lock:#{config[:cluster_name]}:#{config[:check]}"
    interval = cluster_check[:interval]
    staleness_interval = cluster_check[:staleness_interval] || cluster_check[:interval]

    transaction_body = lambda do 
      status, output = check_aggregate(aggregator.summary(
        staleness_interval, child_cluster_name))
      if child_cluster_name
        output = "Cluster: #{child_cluster_name}\n" + output
      end
      msg = "Cluster check successfully executed, with output: #{status}: #{output}"
      if config[:dryrun]
        msg = "Dry run " + msg
      else
        logger.info output
        send_payload EXIT_CODES[status], output, child_cluster_name
      end
      return :ok, msg
    end 

    if config[:dryrun]
      return transaction_body.call
    else 
        mutex = TinyRedis::Mutex.new(redis, lock_key, interval, logger)
        mutex.run_with_lock_or_skip do
          return transaction_body.call
        end
    end

    if (ttl = mutex.ttl) && ttl >= 0
      return :ok, "Cluster check did not execute, lock expires in #{ttl}"
    end

    if ttl.nil?
      return :ok, "Cluster check did not execute, lock expired sooner than round-trip time to redis server"
    end

    return :critical, "Cluster check did not execute, ttl: #{ttl.inspect}"
  rescue SocketError => e
    return :unknown, "Can't connect to Redis at #{redis.host}:#{redis.port}: #{e.message}"
  rescue NoServersFound => e
    if config[:ignore_nohosts]
      return :ok, "Cluster check did not find any hosts: #{e.message}"
    else
     return :unknown, "#{e.message}"
    end
  rescue RuntimeError => e
    return :critical, "#{e.message} (#{e.class}): #{e.backtrace.inspect}"
  end
  
  def logger
    @logger ||= Logger.new($stdout).tap do |logger|
      logger.formatter = proc {|_, _, _, msg| msg} if logger.respond_to? :formatter=
      logger.level = !!config[:verbose] ? Logger::DEBUG : Logger::INFO
    end
  end

  def check_sensu_version
    # good enough
    Sensu::VERSION.split('.')[1].to_i > 12
  end

  EXIT_CODES = Sensu::Plugin::EXIT_CODES

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
    total, ok, silenced, stale, failing = summary.values_at(:total, :ok, :silenced, :stale, :failing)
    return 'OK', 'No servers running the check' if total.zero?

    eff_total = total - silenced * (config[:silenced] ? 1 : 0)
    return 'OK', 'All hosts silenced' if eff_total.zero?

    ok_pct  = (100 * ok / eff_total.to_f).to_i

    # Loop through the arrays and split the hostname so we get a short hostname
    message = "#{ok} OK out of #{eff_total} total."
    message << " #{silenced} silenced." if config[:silenced] && silenced > 0
    message << " #{stale.size} stale." unless stale.empty?
    if config[:num_critical]
      message << " #{eff_total} OK, #{failing.size} FAIL, #{silenced} SILENT, #{stale.size} STALE, #{config[:num_critical]}; FAIL threshold: #{config[:num_critical]}."
    else
      message << " #{ok_pct}% OK, #{config[:pct_critical]}% threshold."
    end
    message << "\nStale hosts: #{stale.map{|host| host.split('.').first}.sort[0..10].join ','}" unless stale.empty?
    message << "\nFailing hosts: #{failing.map{|host| host.split('.').first}.sort[0..10].join ','}" unless failing.empty?
    message << "\nMinimum number of hosts required is #{config[:min_nodes]} and only #{ok} found" if ok < config[:min_nodes]

    if config[:num_critical]
      state = ok >= config[:num_critical] ? 'OK': 'CRITICAL'
    else
      state = ok_pct >= config[:pct_critical] ? 'OK' : 'CRITICAL'
    end
    state = ok >= config[:min_nodes] ? state : 'CRITICAL'
    return state, message
  end

  def sensu_settings
    @sensu_settings ||=
      Sensu::Settings.get(:config_dirs => ["/etc/sensu/conf.d"]) or
      raise "Sensu settings not available"
  end

  def send_payload(status, output, child_cluster_name)
    if child_cluster_name
        source = config[:cluster_name] + '_' + child_cluster_name
    else
        source = config[:cluster_name]
    end
    payload = cluster_check.merge(
      :status => status,
      :output => output,
      :source => source,
      :name   => config[:check])
    payload.delete :command

    sock = TCPSocket.new('localhost', 3030)
    sock.puts payload.to_json
    sock.close
  end

  def cluster_check
    return {} if ENV['DEBUG']
    return JSON.parse(ENV['DEBUG_CC']) if ENV['DEBUG_CC']

    @cluster_check ||=
      sensu_settings[:checks][:"#{config[:cluster_name]}_#{config[:check]}"] or
        raise "#{config[:cluster_name]}_#{config[:check]} not found"
  end
end


class RedisCheckAggregate
  attr_accessor :logger

  def initialize(redis, check, logger, cluster_name, raise_no_server_found)
    @check  = check
    @redis  = redis
    @logger = logger
    @cluster_name = cluster_name
    @raise_no_server_found = raise_no_server_found
  end

  def summary(interval, child_cluster_name=nil)
    # we only care about entries with executed timestamp
    all     = last_execution(find_servers).select{|_,data| data[0]}
    if child_cluster_name
      all = all.select {|_, data| data[2]==child_cluster_name}
    end
    active  = all.select { |_, data| data[0].to_i >= Time.now.to_i - interval }

    logger.debug "All #{all.length} hosts' latest result with timestamp for check #@check:\n#{all}\n\n"
    logger.debug "All #{active.length} hosts with #@check that have responded in the last #{interval} seconds:\n#{active}\n\n"

    stale = all.keys - active.keys
    failing = active.select{ |_,data| data[1].to_i == 2}.to_a.map(&:first)

    unless stale.empty?
      logger.info "The results for the following #{stale.length} hosts are stale (occured more than #{interval} seconds ago):\n#{stale}\n\n"
    end

    unless failing.empty?
      logger.info "The following #{failing.length} hosts are failing the check #{@check}:\n#{failing}\n\n"
    end

    { :stale    => stale,
      :failing  => failing,
      :total    => all.size,
      :ok       => active.count{ |_,data| data[1].to_i == 0 },
      :silenced => all.count do |server, time|
        [server, @check, "#{server}/#@check"].map{|s| "stash:silence/#{s}"}.
          any? {|key| @redis.get(key) }
      end }
  end

  def child_cluster_names()
     last_execution(find_servers).values.map{|(time,_,name)| name if time && name && !name.empty?}.compact.uniq
  end

  def find_servers
    # TODO: reimplement using @redis.scan for webscale
    @servers ||= begin
      keys = @redis.keys("result:*:#@check") || []
      raise NoServersFound if @raise_no_server_found && keys.empty?
      keys.map {|key| key.split(':')[1] }.reject {|s| s == @cluster_name }
    end
  end

  # Returns { server_name => [timestamp, status, cluster_name], ... }
  def last_execution(servers)
    servers.inject({}) do |hash, server|
      begin
        jvalues = @redis.get("result:#{server}:#@check")
        values = JSON.parse(jvalues)
        values2 = values.values_at(
          "executed",
          "status",
          "cluster_name"  # monitored cluster, not sensu cluster.
        )
        hash.merge!(server => values2)
      rescue
        hash
      end
    end
  end
end
