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

      pool = ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        # If this is slow we'll pay the cost on every checkout instead of all at
        # once at boot time. Redis is pretty light so this is usually fine,
        # just keep an eye on latency.
        Familia.create_dbclient(uri) # Factory for new Redis connections
      end

      # Configure Familia
      Familia.configure do |config|
        config.uri = uri

        # Provider pattern: Familia calls this lambda to get connections
        # Returns pooled connection, pool.with handles checkout/checkin automatically
        config.connection_provider = ->(provided_uri) do
          # NOTE: The caller still has to remember to give it back. We might want
          # to wrap this in a decorator that yells if the connection is used
          # outside the block.
          pool.with { |conn| conn }
        end

        config.transaction_mode = :warn
        config.pipeline_mode    = :warn
      end

      # Verify connectivity using pool (tests first connection only)
      ping_result = pool.with { |conn| conn.ping }
      OT.ld "Connected #{Familia.members.size} models to DB 0 via connection pool " \
            "(size: #{pool_size}, timeout: #{pool_timeout}s) - #{ping_result}"

      # Optional: Single migration flag for entire DB 0
      dbkey      = Familia.join(%w[ots migration_needed db_0])
      first_time = pool.with { |conn| conn.setnx(dbkey, '1') } # Direct pool usage for setup
      OT.ld "[connect_databases] Setting #{dbkey} to '1' (already set? #{!first_time})"
    end
  end
end
