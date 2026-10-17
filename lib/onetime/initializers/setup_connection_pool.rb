# lib/onetime/initializers/setup_connection_pool.rb
#
# frozen_string_literal: true

require 'connection_pool'

require_relative '../connection_pinning'

module Onetime
  module Initializers
    # SetupConnectionPool initializer
    #
    # Sets up a ConnectionPool for Redis/Valkey database connections. Configures
    # Familia with thread-safe connection pooling for all database operations.
    # Must run after configure_familia_uri sets Familia.uri.
    #
    # Runtime state set:
    # - Onetime::Runtime.infrastructure.database_pool
    #
    class SetupConnectionPool < Onetime::Boot::Initializer
      @depends_on = [:familia_config]
      @provides   = [:database]

      def execute(_context)
        setup_connection_pool
      end

      private

      def setup_connection_pool
      # NOTE: Familia.uri is already configured by configure_familia_uri initializer
      # which runs before this method. We use it here for connection pooling.
      uri = Familia.uri

      OT.ld "[init] Connect database: uri: #{OT::Utils.redact_uri_userinfo(uri)}"
      OT.ld "[init] Connect database: models: #{Familia.members.map(&:to_s)}"

      # Validate that models have been loaded
      if Familia.members.empty?
        raise Onetime::Problem, 'No known Familia members. Models need to load before boot!'
      end

      # Create connection pool - manages Redis connections for thread safety
      pool_size    = ENV.fetch('FAMILIA_POOL_SIZE', 25).to_i
      pool_timeout = ENV.fetch('FAMILIA_POOL_TIMEOUT', 5).to_i
      parsed_uri   = Familia.normalize_uri(uri)

      # Belt-and-suspenders reconnection resilience:
      # 1. ConnectionPool retries checkout once on connection errors
      # 2. Redis driver retries stale connections on the
      #    Onetime::DATABASE_RECONNECT_ATTEMPTS ladder
      database_pool = ConnectionPool.new(size: pool_size, timeout: pool_timeout, reconnect_attempts: 4) do
        Onetime.create_pooled_dbclient(parsed_uri)
      end

      # Configure Familia connection provider and transaction settings
      # Note: config.uri is already set by configure_familia_uri initializer
      Familia.configure do |config|
        # Provider pattern: Familia calls this lambda to get connections.
        # The pinned path and the pool.with path are described on
        # Onetime.pooled_connection_provider (lib/onetime/connection_pinning.rb).
        config.connection_provider = Onetime.pooled_connection_provider(database_pool)

        config.transaction_mode = :warn
        config.pipelined_mode   = :warn
      end

      # Verify connectivity using pool (tests first connection + reconnection config)
      ping_result = database_pool.with { |conn| conn.ping }
      OT.ld "[init] Connected #{Familia.members.size} models to DB 0 via connection pool " \
            "(size: #{pool_size}, timeout: #{pool_timeout}s) - #{ping_result}"

      # Display database connection milestone
      model_count = Familia.members.size
      db_host     = parsed_uri.conf[:host] || 'localhost'
      db_port     = parsed_uri.conf[:port] || 6379
      db_info     = "#{db_host}:#{db_port}/#{parsed_uri.conf[:db] || 0}"

      OT.log_box(
        [
          "✅ DATABASE: Connected #{model_count} models to Redis",
          "   Location: #{db_info}",
        ],
        level: :debug,
      )

      # Set runtime state
      Onetime::Runtime.update_infrastructure(database_pool: database_pool)
      end
    end
  end
end
