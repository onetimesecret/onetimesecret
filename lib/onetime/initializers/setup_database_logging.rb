# frozen_string_literal: true

# lib/onetime/initializers/setup_database_logging.rb

require 'familia'

module Onetime
  module Initializers
    # Configures Familia's DatabaseLogger middleware for Redis command logging
    #
    # This initializer enables Familia's built-in DatabaseLogger middleware
    # to capture and log Redis commands executed through Familia models.
    # It must be called BEFORE connect_databases to ensure the middleware
    # is registered before any connections are created.
    #
    # Familia handles middleware registration automatically when
    # `enable_database_logging` is set to true.
    #
    # The logger is enabled when:
    # - FAMILIA_DEBUG environment variable is set (any truthy value)
    # - DEBUG_REDIS environment variable is set (any truthy value)
    # - redis.debug is true in configuration
    #
    # @example Development usage
    #   FAMILIA_DEBUG=1 bundle exec thin start
    #   # Logs all Redis commands to STDERR
    #
    # @example Testing usage
    #   FAMILIA_DEBUG=1 bundle exec try --agent try/models/
    #   # Shows Redis commands in tryouts output
    #
    # @example Programmatic usage in tests
    #   commands = DatabaseLogger.capture_commands do
    #     customer = Customer.create(email: 'test@example.com')
    #   end
    #   commands.first[:command] #=> ["HSET", ...]
    #
    # @return [void]
    # @see https://github.com/delano/familia Familia gem documentation
    #
    def setup_database_logging
      # Check if debug logging is enabled via environment or config
      debug_enabled = ENV['FAMILIA_DEBUG'].to_s =~ /^(1|true|yes|on)$/i ||
                      ENV['DEBUG_DATABASE'].to_s =~ /^(1|true|yes|on)$/i ||
                      ENV['DEBUG_VALKEY'].to_s =~ /^(1|true|yes|on)$/i ||
                      ENV['DEBUG_REDIS'].to_s =~ /^(1|true|yes|on)$/i ||
                      (OT.conf && OT.conf.dig('redis', 'debug'))

      if debug_enabled
         # Configure Familia logger for Redis command output
         DatabaseLogger.logger           = Logger.new($stderr)
         DatabaseLogger.logger.level     = Logger::DEBUG
         DatabaseLogger.logger.formatter = proc do |severity, datetime, progname, msg|
           "[#{datetime.strftime('%H:%M:%S.%L')}] #{severity}: #{msg}\n"
         end

         # Enable Familia's database logging (automatically registers middleware)
         Familia.enable_database_logging = true

         OT.ld '[setup_database_logging] Database command logging enabled via Familia'
      else
        # Disable database logging (no middleware overhead)
        Familia.enable_database_logging = false
        OT.ld '[setup_database_logging] Database command logging disabled'
      end
    rescue StandardError => ex
      OT.le "[setup_database_logging] Failed to setup database logging: #{ex.message}"
      OT.ld ex.backtrace.join("\n")
      # Continue boot process - logging is optional functionality
    end
  end
end
