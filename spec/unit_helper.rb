require 'simplecov'
SimpleCov.start

# this is hacky but we really don't want to depend on sensu just for spec
IN_RSPEC = true

module Sensu
  VERSION = "0.13"

  module Plugin
    EXIT_CODES = {
      'OK'       => 0,
      'WARNING'  => 1,
      'CRITICAL' => 2,
      'UNKNOWN'  => 3 }

    class Check
      class CLI
        def self.method_missing(*args); end
      end
    end

    module Utils
      def ok(*args)
        Sensu::Plugin::EXIT_CODES['OK']
      end
    end

  end
end
