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
      @depends_on = [:legacy_check]
      @provides   = [:database]

      def execute(_context)
        setup_connection_pool
      end

      private

      def setup_connection_pool
      # NOTE: Familia.uri is already configured by configure_familia_uri initializer
      # which runs before this method. We use it here for connection pooling.
      uri = Familia.uri

      OT.ld "[init] Connect database: uri: #{uri}"
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
      # 2. Redis driver retries once with minimal delay for stale connections
      database_pool = ConnectionPool.new(size: pool_size, timeout: pool_timeout, reconnect_attempts: 4) do
        Redis.new(
          parsed_uri.conf.merge(
            reconnect_attempts: [
              0.05, # 50ms delay before first retry
              0.20, # 200ms for 2nd
              1,    # 1000ms
              2,    # wait a full 2000s for final retry
            ],
          ),
        )
      end

      # Configure Familia connection provider and transaction settings
      # Note: config.uri is already set by configure_familia_uri initializer
      Familia.configure do |config|
        # Provider pattern: Familia calls this lambda to get connections.
        #
        # Pinned path (preferred for WATCH/MULTI and any read-then-write flow):
        # callers wrap their critical section in Onetime.with_pinned_dbclient,
        # which pushes a single pool.with checkout onto a fiber-local stack.
        # While the stack is populated, every Familia.dbclient call on this
        # fiber resolves to that same conn, so all commands land on one socket.
        #
        # Unpinned path: pool.with checks a conn out and immediately checks it
        # back in — the caller uses a reference that is technically released.
        # This is safe for single-command ad-hoc calls (the overwhelming
        # majority) but must not be relied on for multi-step coherence.
        config.connection_provider = ->(_provided_uri) do
          stack = Fiber[:ots_pinned_dbclient_stack]
          next stack.last if stack && !stack.empty?

          database_pool.with { |conn| conn }
        end

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
