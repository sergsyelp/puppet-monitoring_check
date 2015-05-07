#
# tiny_redis
#
# redis connectivity helpers
#

require 'socket'

module TinyRedis

  class Mutex
    attr_reader :redis, :key, :interval, :now, :logger

    def initialize(redis, key, interval, logger = $stdout)
      @redis    = redis

      raise "Redis connection check failed" unless "hello" == redis.echo("hello")

      @key      = key
      @interval = interval.to_i
      @now      = Time.now.to_i
      @logger   = logger
    end

    def run_with_lock_or_skip
      # TODO
      # assumes clocks on hosts working with this lock are fairly in sync -
      # may not be a good assumption in all cases but will do for now

      expire if ENV['DEBUG_UNLOCK']

      if redis.setnx(key, now) == 1
        begin
          expire interval
          yield
          nil
        rescue => e
          expire
          raise e
        end
      else
        redis.pttl(key).to_f/1000
      end
    end

    private

    def expire(seconds=0)
      redis.pexpire(@key, seconds*1000)
    end

  end

  class Client

    RN = "\r\n"

    def initialize(host='localhost', port=6379)
      @host = host
      @port = port
    end

    def socket
      @socket ||= TCPSocket.new(@host, @port)
    end

    def method_missing(method, *args)
      args.unshift method
      data = ["*#{args.size}", *args.map {|arg| "$#{arg.to_s.size}#{RN}#{arg}"}]
      socket.write(data.join(RN) << RN)
      parse_response
    end

    def parse_response
      case socket.gets
        when /^\+(.*)\r\n$/ then $1
        when /^:(\d+)\r\n$/ then $1.to_i
        when /^-(.*)\r\n$/  then raise "Redis error: #{$1}"
        when /^\$([-\d]+)\r\n$/
          $1.to_i >= 0 ? socket.read($1.to_i+2)[0..-3] : nil
        when /^\*([-\d]+)\r\n$/
          $1.to_i > 0 ? (1..$1.to_i).inject([]) { |a,_| a << parse_response } : nil
      end
    end

    def close
      socket.close
    end

  end
end
