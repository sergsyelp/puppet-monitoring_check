require "#{File.dirname(__FILE__)}/../unit_helper"
require "#{File.dirname(__FILE__)}/../../files/check-cluster"

describe CheckCluster do
  let(:config) do
    { :check        => :test_check,
      :cluster_name => :test_cluster,
      :pct_critical => 50,
      :min_nodes    => 0 }
  end

  let(:sensu_settings) do
    { :checks => {
        :test_cluster_test_check => {
          :interval => 300,
          :staleness_interval => '12h' } } }
  end

  let(:redis)  do
    double(:redis).tap do |redis|
      redis.stub(
        :echo    => "hello",
        :setnx   => 1,  # key found
        :pexpire => 1,  # timeout was set
        :get     => Time.now.to_i - 5,
        :host    => '127.0.0.1',
        :port    => 7777, )
    end
  end

  let(:logger) { Logger.new(StringIO.new("")) }

  let(:aggregator) do
    double(:aggregator).tap do |agg|
      agg.stub(:summary).and_return({
          :total => 1,
          :ok => 1,
          :silenced => 0,
          :failing => [],
          :stale => []
      })
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

  context "status" do
    context "should be OK" do
      it "when all is good" do
        expect_status :ok, /Cluster check successfully executed/
        expect_payload :ok, /0%/
        check.run
      end

      it "when lock was not acquired" do
        redis.stub(:setnx).and_return 0
        redis.stub(:pttl).and_return 10000.0
        expect_status :ok, /expires in 10/
        check.run
      end

      it "when lock expired" do
        redis.stub(:setnx).and_return 0
        redis.stub(:pttl).and_return 0.0
        expect_status :ok, /did not execute/
        check.run
      end

      it "when lock expired before " do
        redis.stub(:setnx).and_return 0
        redis.stub(:pttl).and_return nil
        expect_status :ok, /did not execute/
        check.run
      end
    end

    context "should be CRITICAL" do
      it "when exception happened on :setnx" do
        expect(redis).to receive(:setnx).and_raise "rspec error"
        expect_status :critical, /rspec error/
        check.run
      end
    end

    context "should be UNKNOWN" do
      it "when SocketError happens" do
        expect(TinyRedis::Mutex).to receive(:new).and_raise SocketError
        expect_status :unknown, /127.0.0.1:7777: SocketError$/
        check.run
      end

      it "when wrong version of sensu" do
        stub_const("Sensu::VERSION", "0.12")
        expect_status :unknown, "Sensu <0.13 is not supported"
        check.stub(:locked_run).and_return nil
        check.run
      end
    end
  end

  context "payload" do
    context "should be CRITICAL" do
      it "when reached critical threshold" do
        status, message = check.send(
            :check_aggregate, :ok => 40, :total => 100, :silenced => 0,
            :failing => ["somehost.hostname.com", "anotherhost.example.com"],
            :stale => [])
        expect(status).to eq("CRITICAL")
        expect(message).to match(/40%/)
      end
    end

    context "should include number of stale hosts in output" do
      it "when stale hosts are found" do
        _, message = check.send(
            :check_aggregate, :ok => 90, :total => 100, :silenced => 0,
            :failing => [], :stale => [ 'host1', 'host2' ])
        expect(message).to match(/ 2 stale\./)
      end
    end

    context "should be CRITICAL" do
      let(:config) { super().merge(:min_nodes => 10) }
      it "when minimum nodes not met" do
        status, message = check.send(
            :check_aggregate, :ok => 5, :total => 5, :silenced => 0,
            :failing => [], :stale => [])
        expect(status).to eq("CRITICAL")
        expect(message).to match(/Minimum/)
      end
    end
  end

  # implementation details
  it "should run within a lock" do
    expect(redis).to receive(:setnx).and_return(1)
    expect_status :ok, /Cluster check successfully executed/
    expect_payload :ok, /0%/
    check.run
  end
end
