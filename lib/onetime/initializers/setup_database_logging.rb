# lib/onetime/initializers/setup_database_logging.rb

module Onetime
  module Initializers
    attr_accessor :redis_pool

    # Configures Familia's DatabaseLogger middleware for Redis command logging
    #
    # Must be called BEFORE connect_databases to ensure the middleware
    # is registered before any connections are created.
    #
    # @return [void]
    #
    def setup_database_logging
      if OT.env?(:production)
        Familia.enable_database_logging = false
        return OT.lw "[setup_database_logging] Blocked in #{OT.env}"
      end

      # Check multiple environment variables for database debugging specifically
      debug_enabled = %w[DEBUG_DATABASE DEBUG_VALKEY DEBUG_REDIS].any? do |val|
        Onetime::Utils.yes?(ENV.fetch(val, nil))
      end

      # Enables Familia's database logging (automatically registers middleware)
      Familia.enable_database_logging = debug_enabled

      status = debug_enabled ? 'enabled' : 'disabled'
      OT.ld "[setup_database_logging] Database command logging #{status}"
    rescue StandardError => ex
      OT.le "[setup_database_logging] Error: #{ex.message}"
      OT.ld ex.backtrace.join("\n")
      # Continue boot process - logging is optional functionality
    end
  end
end
