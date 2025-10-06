# lib/onetime/initializers/connect_databases.rb

require 'connection_pool'

module Onetime
  module Initializers
    # Configures Familia with connection pooling for all models.
    #
    # Sets up a ConnectionPool that Familia uses for all database
    # operations across models in DB 0.
    #
    # @example
    #   connect_databases
    #
    # @return [void]
    #
    def connect_databases
      uri = OT.conf.dig('redis', 'uri')

      OT.ld "[connect_databases] uri: #{uri}"
      OT.ld "[connect_databases] models: #{Familia.members.map(&:to_s)}"

      # Validate that models have been loaded
      if Familia.members.empty?
        raise Onetime::Problem, 'No known Familia members. Models need to load before calling boot!'
      end

      # Create connection pool - manages Redis connections for thread safety
      pool_size    = ENV.fetch('FAMILIA_POOL_SIZE', 25).to_i
      pool_timeout = ENV.fetch('FAMILIA_POOL_TIMEOUT', 5).to_i

      # Belt-and-suspenders reconnection resilience:
      # 1. ConnectionPool retries checkout once on connection errors
      # 2. Redis driver retries once with minimal delay for stale connections
      OT.redis_pool = ConnectionPool.new(size: pool_size, timeout: pool_timeout, reconnect_attempts: 1) do
        parsed_uri = Familia.normalize_uri(uri)
        Redis.new(parsed_uri.conf.merge(
          reconnect_attempts: [
            0.05, # 50ms delay before first retry
            0.20, # 200ms for 2nd
            1,    # 1000ms
            2,    # wait a full 2000s for final retry
          ]
        ))
      end

      # Configure Familia
      Familia.configure do |config|
        config.uri = uri

        # Provider pattern: Familia calls this lambda to get connections
        # Returns pooled connection, pool.with handles checkout/checkin automatically
        # Reconnection handled at pool + Redis level prevents "idle connection death"
        config.connection_provider = ->(provided_uri) do
          OT.redis_pool.with { |conn| conn }
        end

        config.transaction_mode = :warn
        config.pipeline_mode    = :warn
      end

      # Verify connectivity using pool (tests first connection + reconnection config)
      ping_result = OT.redis_pool.with { |conn| conn.ping }
      OT.ld "Connected #{Familia.members.size} models to DB 0 via connection pool " \
            "(size: #{pool_size}, timeout: #{pool_timeout}s) - #{ping_result}"

      # Optional: Single migration flag for entire DB 0
      dbkey      = Familia.join(%w[ots migration_needed db_0])
      first_time = OT.redis_pool.with { |conn| conn.setnx(dbkey, '1') } # Direct pool usage for setup
      OT.ld "[connect_databases] Setting #{dbkey} to '1' (already set? #{!first_time})"
    end
  end
end
