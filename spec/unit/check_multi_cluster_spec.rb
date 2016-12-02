require "#{File.dirname(__FILE__)}/../unit_helper"
require "#{File.dirname(__FILE__)}/../../files/check-cluster"
require 'byebug'
require 'pry-byebug'

def child_check_name
    "test_child_check"
end

describe CheckCluster do
  let(:config) do
    { :check        => child_check_name, # name of child check to be aggregated
      :cluster_name => :test_cluster,  # name of parent cluster, not children
      :multi_cluster => true,  # e.g. we're looking for groups of children
      :verbose => true,  # turn on debug logging
      :pct_critical => 50,
      :min_nodes    => 0 }
  end

  let(:sensu_settings) do
    { :checks => {
        :test_cluster_test_child_check => {
          :interval => 300,
          :staleness_interval => '12h' } } }
  end

  let(:redis) do
    double(:redis).tap do |redis|
      redis.stub(
        :echo    => "hello",
        :setnx   => 1,
        :pexpire => 1,
        :host    => '127.0.0.1',
        :port    => 7777, )
      redis.stub(:keys) do |query|
        if query == "result:*:#{child_check_name}" then
          [
            "result:10-10-10-101-uswest1bdevprod.dev.yelpcorp.com:#{child_check_name}",
            "result:10-10-10-111-uswest1bdevprod.dev.yelpcorp.com:#{child_check_name}",
            "result:10-10-10-121-uswest1bdevprod.dev.yelpcorp.com:#{child_check_name}",
            "result:10-10-10-102-uswest1bdevprod.dev.yelpcorp.com:#{child_check_name}",
            "result:10-10-10-112-uswest1bdevprod.dev.yelpcorp.com:#{child_check_name}",
            "result:10-10-10-122-uswest1bdevprod.dev.yelpcorp.com:#{child_check_name}"
          ]
        else
            raise "unexpected query: #{query}"
        end
      end
      redis.stub(:get) do |query|
        match = /result:([^:]+):#{child_check_name}/.match(query)
        if match then
          host = match[1]
          # fabricate cluster_name using last char/digit of host IP
          cluster_name = "cluster_" + host.sub(/.*[-0-9]+(\d)-.*/, '\1')
#          binding.pry
          "{
            \"interval\": 300,
            \"standalone\": true,
            \"timeout\": 300,
            \"alert_after\": 300,
            \"ticket\": false,
            \"page\": true,
            \"cluster_name\": \"#{cluster_name}\",
            \"name\": \"#{child_check_name}\",
            \"issued\": #{Time.now.to_i - 5},
            \"executed\": #{Time.now.to_i - 5},
            \"duration\": 0.002,
            \"status\": 0,
            \"type\": \"standard\"
          }"
        else
          # copied from check_cluster_spec.rb - not sure what it's for yet
          Time.now.to_i - 5
        end
      end
    end
  end

  let(:logger) { Logger.new(StringIO.new("")) }

  let(:check) do
    CheckCluster.new.tap do |check|
      check.stub(
        :config         => config,
        :sensu_settings => sensu_settings,
        :redis          => redis,
        :logger         => logger,
#        :aggregator     => aggregator,
        :unknown        => nil)
    end
  end

  def expect_status(code, message)
    expect(check).to receive(code).with(message)
  end

  def expect_payload(code, message)
    expect(check).to receive(:send_payload).with(
      Sensu::Plugin::EXIT_CODES[code.to_s.upcase],
      message
    ).and_return(nil)
  end

  context "implementation details" do
    it "fetches server names" do
      expect(check.aggregator.find_servers.size).to eq(6)
    end

    it "groups by cluster_name" do
      agg = check.aggregator
      expect(agg.last_execution(agg.find_servers).size).to eq(6)
      expect(agg.child_cluster_names).to eq(Set.new(["cluster_1","cluster_2"]))
    end

    it "gets last execution details right" do
        agg = check.aggregator
        servers = ["result:10-10-10-101-uswest1bdevprod.dev.yelpcorp.com"]
        le = agg.last_execution(servers)
        expect(le.keys).to eq(
            ["result:10-10-10-101-uswest1bdevprod.dev.yelpcorp.com"]
        )
#            {"result:10-10-10-101-uswest1bdevprod.dev.yelpcorp.com"=>[1480591226, 0, "cluster_1"]}
    end
  end

  context "'end-to-end'" do
    it "is written that" do
        pending("figuring out what we need to write here")
        fail
    end
  end
end
