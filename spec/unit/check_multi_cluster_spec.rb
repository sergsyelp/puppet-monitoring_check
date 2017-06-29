require "#{File.dirname(__FILE__)}/../unit_helper"
require "#{File.dirname(__FILE__)}/../../files/check-cluster"

def child_check_name
    "test_child_check"
end

def redis_keys(query)
  if query == "result:*:#{child_check_name}" then
    [
      "result:10-10-10-101-dcname.dev.yelpcorp.com:#{child_check_name}",
      "result:10-10-10-111-dcname.dev.yelpcorp.com:#{child_check_name}",
      "result:10-10-10-121-dcname.dev.yelpcorp.com:#{child_check_name}",
      "result:10-10-10-102-dcname.dev.yelpcorp.com:#{child_check_name}",
      "result:10-10-10-112-dcname.dev.yelpcorp.com:#{child_check_name}",
      "result:10-10-10-122-dcname.dev.yelpcorp.com:#{child_check_name}"
    ]
  else
      raise "unexpected query: #{query}"
  end
end

def redis_no_keys(query)
  if query == "result:*:#{child_check_name}" then
    []
  else
      raise "unexpected query: #{query}"
  end
end

def cluster_name_from_host(host)
  # fabricate cluster_name using last char/digit of host IP
  "cluster_" + host.sub(/.*[-0-9]+(\d)-.*/, '\1')
end

def redis_get(query)
  match = /result:([^:]+):#{child_check_name}/.match(query)
  if match then
    host = match[1]
    # fabricate cluster_name using last char/digit of host IP
    cluster_name = cluster_name_from_host(host)
    {
      "interval" => 300,
      "standalone" => true,
      "timeout" => 300,
      "alert_after" => 300,
      "ticket" => false,
      "page" => true,
      "cluster_name" => cluster_name,
      "name" => child_check_name,
      "issued" => Time.now.to_i - 5,
      "executed" => Time.now.to_i - 5,
      "duration" => 0.002,
      "status" => 0,
      "type" => "standard",
    }.to_json
  end
end

def redis_get_half_bad(query)
  intermediate = redis_get(query)
  if !intermediate then
    return intermediate
  end
  result = JSON.parse(intermediate)
  if result["cluster_name"] == "cluster_1" then
    result["status"] = 2
  end
  result.to_json
end

def redis_get_all_bad(query)
  intermediate = redis_get(query)
  if !intermediate then
    return intermediate
  end
  result = JSON.parse(intermediate)
  if ["cluster_1", "cluster_2"].include?(result["cluster_name"]) then
    result["status"] = 2
  end
  result.to_json
end

describe CheckCluster do
  let(:config) do
    { :check        => child_check_name, # name of child check to be aggregated
      :cluster_name => :test_cluster,  # name of parent cluster, not children
      :multi_cluster => true,  # e.g. we're looking for groups of children
      :ignore_nohosts => true, # some sensu clusters might not have any child clusters
      :verbose => true,  # turn on debug logging
      :pct_critical => 50,
      :min_nodes    => 0 }
  end

  let(:sensu_settings) do
    { :checks => {
        :test_cluster_test_child_check => {
          :interval => 300,
          :staleness_interval => 12*60*60  # '12h'
        } } }
  end

  let(:redis) do
    double(:redis).tap do |redis|
      redis.stub(
        :echo    => "hello",
        :setnx   => 1,
        :pexpire => 1,
        :host    => '127.0.0.1',
        :port    => 7777, )
      redis.stub(:keys) do |query| redis_keys(query) end
      redis.stub(:get) do |query| redis_get(query) end
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
        :unknown        => nil)
    end
  end

  def expect_status(code, message)
    expect(check).to receive(code).with(message)
  end

  def expect_payload(code, message, child_cluster_name)
    expect(check).to receive(:send_payload).with(
      Sensu::Plugin::EXIT_CODES[code.to_s.upcase],
      message,
      child_cluster_name
    ).and_return(nil)
  end

  context "implementation details" do
    it "fetches server names" do
      expect(check.aggregator.find_servers.size).to eq(6)
    end

    it "groups by cluster_name" do
      agg = check.aggregator
      expect(agg.last_execution(agg.find_servers).size).to eq(6)
      expect(agg.child_cluster_names).to eq(["cluster_1","cluster_2"])
    end

    it "gets last execution details right" do
      agg = check.aggregator
      servers = ["result:10-10-10-101-dcname.dev.yelpcorp.com"]
      le = agg.last_execution(servers)
      expect(le.keys).to eq(
        ["result:10-10-10-101-dcname.dev.yelpcorp.com"]
      )
    end
  end

  context "end-to-end" do
    context "no clusters there at all" do
        let(:redis) do  # TODO(pmu) want to figure out DRY - perhaps overriding 'let' per https://github.com/rspec/rspec-core/issues/294
          double(:redis).tap do |redis|
            redis.stub(
              :echo    => "hello",
              :setnx   => 1,
              :pexpire => 1,
              :host    => '127.0.0.1',
              :port    => 7777, )
            redis.stub(:keys) do |query| redis_no_keys(query) end
          end
        end
        it "should be quiet: e.g. no exceptions such as NoServersFound" do
          expect_status :ok, /No child clusters found in this sensu cluster/
          check.run
        end
        context "not ignoring nohosts" do
          let(:config) { super().merge ignore_nohosts: false }
          it "should be noisy: we've said we care about missing hosts" do
            expect{ check.run }.to raise_error(NoServersFound)
          end
        end
    end
    it "no clusters failing" do
      expect_payload :ok, /3 OK out of 3 total. 100% OK, 50% threshold/, 'cluster_1'
      expect_payload :ok, /3 OK out of 3 total. 100% OK, 50% threshold/, 'cluster_2'
      expect_status :ok, /Cluster check successfully executed/
      check.run
    end
    context "single cluster failing" do
      let(:redis) do  # TODO(pmu) want to figure out DRY - perhaps overriding 'let' per https://github.com/rspec/rspec-core/issues/294
        double(:redis).tap do |redis|
          redis.stub(
            :echo    => "hello",
            :setnx   => 1,
            :pexpire => 1,
            :host    => '127.0.0.1',
            :port    => 7777, )
          redis.stub(:keys) do |query| redis_keys(query) end
          redis.stub(:get) do |query| redis_get_half_bad(query) end
        end
      end
      it "single cluster failing" do
        expect_payload(
          :critical,
          %r{
            Cluster:\scluster_1\n
            0\sOK\sout\sof\s3\stotal.\s0%\sOK,\s50%\sthreshold.\n
            Failing\shosts:\s10-10-10-101-dcname,
                             10-10-10-111-dcname,
                             10-10-10-121-dcname
            $
          }x,
          'cluster_1'
        )
        expect_payload :ok, /3 OK out of 3 total. 100% OK, 50% threshold/, 'cluster_2'
        expect_status :ok, /Cluster check successfully executed/
        check.run
      end
    end
    context "both clusters failing" do
      let(:redis) do  # TODO(pmu) want to figure out DRY - perhaps overriding 'let' per https://github.com/rspec/rspec-core/issues/294
        double(:redis).tap do |redis|
          redis.stub(
            :echo    => "hello",
            :setnx   => 1,
            :pexpire => 1,
            :host    => '127.0.0.1',
            :port    => 7777, )
          redis.stub(:keys) do |query| redis_keys(query) end
          redis.stub(:get) do |query| redis_get_all_bad(query) end
        end
      end
      it "both clusters failing" do
        expect_payload(
          :critical,
          %r{
            Cluster:\scluster_1\n
            0\sOK\sout\sof\s3\stotal.\s0%\sOK,\s50%\sthreshold.\n
            Failing\shosts:\s10-10-10-101-dcname,
                             10-10-10-111-dcname,
                             10-10-10-121-dcname
            $
          }x,
          'cluster_1'
        )
        expect_payload(
          :critical,
          %r{
            Cluster:\scluster_2\n
            0\sOK\sout\sof\s3\stotal.\s0%\sOK,\s50%\sthreshold.\n
            Failing\shosts:\s10-10-10-102-dcname,
                             10-10-10-112-dcname,
                             10-10-10-122-dcname
            $
          }x,
          'cluster_2'
        )
        expect_status :ok, /Cluster check successfully executed/
        check.run
      end
    end
  end
end
