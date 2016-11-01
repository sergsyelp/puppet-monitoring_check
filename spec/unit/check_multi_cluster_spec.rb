require "#{File.dirname(__FILE__)}/../unit_helper"
require "#{File.dirname(__FILE__)}/../../files/check-cluster"
require 'byebug'
require 'pry-byebug'

describe CheckCluster do
  let(:config) do
    { :check        => :test_child_check, # name of child check to be aggregated
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

  let(:redis)  do
    double(:redis).tap do |redis|
      redis.stub(
        :echo    => "hello",
        :setnx   => 1,
        :pexpire => 1,
        :get     => Time.now.to_i - 5,
        :host    => '127.0.0.1',
        :port    => 7777, )
    end
  end

  let(:logger) { Logger.new(StringIO.new("")) }

  let(:aggregator) do
    double(:aggregator).tap do |agg|
      agg.stub(:summary).and_return({:total => 1, :ok => 1, :silenced => 0, :failing => [], :stale => []})
    end
  end

  let(:check) do
    CheckCluster.new.tap do |check|
      check.stub(
        :config         => config,
        :sensu_settings => sensu_settings,
        :redis          => redis,
        :logger         => logger,
        :aggregator     => aggregator,
        :unknown        => nil)
    end
  end

  def expect_status(code, message)
    expect(check).to receive(code).with(message)
  end

  def expect_payload(code, message)
    expect(check).to receive(:send_payload).with(
      Sensu::Plugin::EXIT_CODES[code.to_s.upcase], message).and_return(nil)
  end

  context "implementation details" do
    it "groups by cluster_name" do
    end
  end

  context "'end-to-end'" do
    it "is written that" do
        pending("figuring out what we need to write here")
        fail
    end
  end
end
