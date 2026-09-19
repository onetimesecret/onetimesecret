# apps/web/auth/database.rb
#
# frozen_string_literal: true

require 'sequel'
require 'logger'

require_relative 'migrator'

module Auth
  module Database
    extend Onetime::LoggerMethods

    # Lazy connection proxy that defers actual database connection until first use.
    #
    # This allows Rodauth plugin to be configured at class-definition time without
    # immediately establishing a database connection. The actual TCP connection
    # and authentication only happens when Rodauth first queries the database
    # (typically during warmup or first request).
    #
    # Benefits:
    # - Faster application boot (no DB connection during require)
    # - Better testability (mocks can be installed before first DB access)
    # - Resilient to database unavailability during initial code loading
    #
    # The proxy delegates all method calls to the underlying Sequel::Database
    # instance, which is created on first access.
    #
    class LazyConnection < BasicObject
      # Include Kernel methods that migrations and other code might need when
      # running in the context of the database (via instance_exec)
      include ::Kernel

      def initialize(&connector)
        @connector      = connector
        @__connection__ = nil
        @mutex          = ::Mutex.new
      end

      def method_missing(method, *, &)
        __connection__.__send__(method, *, &)
      end

      def respond_to_missing?(method, include_private = false)
        __connection__.respond_to?(method, include_private)
      end

      # Explicitly delegate common Sequel::Database methods for better introspection
      def [](table)
        __connection__[table]
      end

      def table_exists?(table)
        __connection__.table_exists?(table)
      end

      # Health check method used by routes/health.rb
      def test_connection
        __connection__.test_connection
      end

      # Type checking methods (BasicObject doesn't have these, but RSpec/Rodauth may need them)
      def is_a?(klass) # rubocop:disable Naming/PredicatePrefix
        __connection__.is_a?(klass)
      end

      def kind_of?(klass)
        __connection__.is_a?(klass)
      end

      def instance_of?(klass)
        __connection__.instance_of?(klass)
      end

      def class
        __connection__.class
      end

      def disconnect
        @mutex.synchronize do
          @__connection__&.disconnect
          @__connection__ = nil
        end
      end

      # Allow checking if connection has been established (useful for tests)
      def __connected__?
        @mutex.synchronize { !@__connection__.nil? }
      end

      # Force connection (useful for warmup)
      def __connect__!
        __connection__
        true
      end

      private

      def __connection__
        @mutex.synchronize do
          @__connection__ ||= @connector.call
        end
      end
    end

    @connection_mutex = Mutex.new

    def self.connection
      # Only create database connection in full mode
      # Simple mode operates without SQL database dependencies
      return nil unless Onetime.auth_config.full_enabled?

      @connection_mutex.synchronize do
        @connection ||= create_lazy_connection
      end
    end

    # Reset the connection (useful for tests)
    def self.reset_connection!
      @connection_mutex.synchronize do
        @connection&.disconnect if @connection.respond_to?(:disconnect)
        @connection = nil
      end
    end

    # Whether the auth database can actually be reached right now.
    #
    # `connection` returns a LazyConnection proxy, which is ALWAYS truthy in
    # full mode — it defers the real connect to first use. So `if db` only
    # answers "is this full mode?", never "is there a usable database?", and a
    # caller that treats it as the latter blows up later at an arbitrary query.
    # This forces the connection behind a rescue so callers that must degrade
    # gracefully (CLI commands, tryouts without a provisioned DB) can ask
    # directly.
    #
    # Not memoized: a database may come up (or go away) during a process's
    # lifetime, and tests reset the connection between examples.
    def self.available?
      conn = connection
      return false if conn.nil?

      conn.__connect__!
      true
    rescue StandardError => ex
      sequel_logger.warn '[Database] Auth database unavailable',
        error: ex.message,
        error_class: ex.class.name
      false
    end

    # Check if a connection has been established
    def self.connected?
      return false unless @connection

      @connection.__connected__?
    end

    # Parses PostgreSQL multi-host connection URLs into Sequel connection hash.
    #
    # PostgreSQL libpq supports comma-separated hosts for failover:
    #   postgresql://user:pass@host1:5432,host2:5432/dbname?sslmode=require
    #
    # But this isn't a valid RFC 3986 URI, so Ruby's URI.parse fails.
    # Sequel needs either a single-host URL or a connection hash.
    #
    # This method extracts the first (primary) host and converts the URL
    # to a Sequel connection hash, which pg gem will handle correctly.
    #
    # @param url [String] PostgreSQL connection URL with comma-separated hosts
    # @return [Hash] Sequel connection parameters
    def self.parse_postgres_multihost_url(url)
      # Extract components using regex since URI.parse won't work
      match = url.match(
        %r{
                ^postgresql://
                (?:([^:@]+)(?::([^@]+))?@)?  # user:password (optional)
                ([^,/]+)                      # first host:port
                (?:,[^/]+)?                   # additional hosts (ignored - use primary)
                (?:/([^?]+))?                 # database name
                (?:\?(.+))?                   # query params
              }x,
      )

      raise ArgumentError, "Invalid PostgreSQL URL format: #{url}" unless match

      user, password, host_port, database, query_string = match.captures

      # Parse host and port from first host
      host, port = host_port.split(':')
      port     ||= '5432'

      # Parse query parameters
      params = {}
      if query_string
        query_string.split('&').each do |param|
          key, value         = param.split('=', 2)
          params[key.to_sym] = value
        end
      end

      # Build Sequel connection hash
      opts = {
        adapter: 'postgres',
        host: host,
        port: port.to_i,
        database: database || 'postgres',
      }

      opts[:user]     = user if user
      opts[:password] = password if password

      # Map PostgreSQL connection params to pg gem options
      opts[:sslmode] = params[:sslmode] if params[:sslmode]

      sequel_logger.info '[Database] Converted multi-host PostgreSQL URL to connection hash',
        host: host,
        port: port,
        database: database,
        has_user: !user.nil?,
        sslmode: params[:sslmode]

      opts
    end

    def self.create_lazy_connection
      LazyConnection.new do
        sequel_logger.info '[Database] Creating Auth database connection'

        # Get database URL from auth config or environment
        database_url = Onetime.auth_config.database_url || 'sqlite://data/auth.db'

        # PostgreSQL multi-host URLs (host1:port1,host2:port2) are not valid URIs
        # Convert them to Sequel's hash format for proper failover support
        connection_opts = if database_url.start_with?('postgresql://') && database_url.split('?').first.include?(',')
          parse_postgres_multihost_url(database_url)
        else
          database_url
        end

        connect(connection_opts)
      end
    end

    # How long a SQLite connection waits for a lock another connection holds.
    # Sequel's own default for its `:timeout` option.
    SQLITE_BUSY_TIMEOUT_MS = 5_000

    # Open the authdb connection. The one place connection options live, so
    # the lazy and the immediate connection cannot drift.
    #
    # ## SQLite: two settings, and both are needed
    #
    # Concurrent sign-ups answered 500 (`SQLite3::BusyException: database is
    # locked` on the accounts INSERT): 7 of 8 parallel POST
    # /auth/create-account on a file-backed authdb. Two separate causes, and
    # fixing either alone changes nothing (measured with four threads that
    # each read, then insert, inside a transaction: three of four fail under
    # either fix alone, none under both):
    #
    # 1. `transaction_mode = :immediate`. Rodauth's create-account reads inside
    #    its transaction before it inserts. Under SQLite's default DEFERRED
    #    mode two connections then both hold a SHARED lock and both ask to
    #    upgrade; SQLite refuses the second AT ONCE, without consulting the
    #    busy handler, because waiting would deadlock. BEGIN IMMEDIATE takes
    #    the write lock up front, where waiting is safe. Read-only
    #    transactions queue behind writers too; on a single-instance SQLite
    #    authdb that is the price of not failing.
    #
    # 2. `busy_handler_timeout=` in place of `busy_timeout`. Sequel's
    #    `:timeout` option calls sqlite3_busy_timeout, which sleeps inside C
    #    while holding Ruby's GVL. In a threaded server the thread that owns
    #    the lock is then unable to run and release it: every waiter burns
    #    the whole timeout and fails anyway. The sqlite3 gem's
    #    busy_handler_timeout= does the same wait and releases the GVL between
    #    attempts. It is set per connection, after Sequel's own setting, which
    #    it replaces.
    #
    # A wait that still outlasts the timeout raises as before. Reaching it
    # takes more queued writers than the server has threads.
    #
    # PostgreSQL needs none of this: a duplicate insert waits on the row and
    # then raises a unique violation, which Rodauth handles.
    #
    # @param connection_opts [String, Hash] a database URL or a Sequel
    #   connection hash
    # @return [Sequel::Database]
    def self.connect(connection_opts)
      sqlite  = connection_opts.is_a?(String) && connection_opts.start_with?('sqlite')
      options = { logger: Onetime.get_logger('Sequel'), sql_log_level: :trace } # SQL at trace level for safety

      if sqlite
        options[:timeout]       = SQLITE_BUSY_TIMEOUT_MS
        options[:after_connect] = ->(conn) { conn.busy_handler_timeout = SQLITE_BUSY_TIMEOUT_MS if conn.respond_to?(:busy_handler_timeout=) }
      end

      Sequel.connect(connection_opts, **options).tap do |db|
        db.extension :date_arithmetic
        db.transaction_mode = :immediate if sqlite
      end
    end

    # Legacy method for compatibility - creates connection immediately
    # Prefer using `connection` which returns a lazy proxy
    def self.create_connection
      sequel_logger.info '[Database] Creating Auth database connection (immediate)'

      database_url = Onetime.auth_config.database_url || 'sqlite://data/auth.db'

      connect(database_url)
    end

    # Ensure database migrations are up to date.
    #
    # This is a convenience method that can work in two modes:
    #
    # 1. **Standalone mode** (CI/scripts): When called without full app boot,
    #    reads AUTH_DATABASE_URL from environment and runs migrations directly.
    #    This is useful for CI scripts that just need to run migrations.
    #
    # 2. **Application mode**: When Onetime.auth_config is available, delegates
    #    to Auth::Migrator.run_if_needed which handles advisory locks, elevated
    #    credentials, and proper logging.
    #
    # Concurrent safety:
    # - PostgreSQL: Uses advisory locks to prevent migration races
    # - SQLite: No advisory lock support (single-instance only)
    #
    # @return [void]
    # @raise [Sequel::Migrator::Error] if migrations fail
    #
    def self.ensure_migrations!
      Sequel.extension :migration

      # Check if we have full app context or running standalone
      if defined?(Onetime) && Onetime.respond_to?(:auth_config) && Onetime.auth_config&.full_enabled?
        # Full app mode - delegate to Migrator with all its features
        Auth::Migrator.run_if_needed
      else
        # Standalone mode - read from environment directly
        database_url = ENV.fetch('AUTH_DATABASE_URL', nil)
        raise 'AUTH_DATABASE_URL environment variable not set' unless database_url

        migrations_dir = File.join(__dir__, 'migrations')
        raise "Migrations directory not found: #{migrations_dir}" unless Dir.exist?(migrations_dir)

        conn = Sequel.connect(database_url)
        begin
          # Use advisory locks for PostgreSQL to handle concurrent boots
          use_advisory_lock = conn.adapter_scheme == :postgres

          Sequel::Migrator.run(
            conn,
            migrations_dir,
            use_transactions: true,
            use_advisory_lock: use_advisory_lock,
          )
        rescue Sequel::AdvisoryLockError
          # Another process is running migrations - this is expected and OK
          puts '[Auth::Database] Migrations already in progress (advisory lock held by another process)'
        ensure
          conn.disconnect
        end
      end
    end
  end
end
