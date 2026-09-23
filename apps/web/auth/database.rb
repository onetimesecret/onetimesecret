# apps/web/auth/database.rb
#
# frozen_string_literal: true

require 'sequel'
require 'logger'

require_relative 'database_connection'
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

    # Converts a multi-host PostgreSQL URL to a Sequel connection hash. See
    # Auth::DatabaseConnection.parse_postgres_multihost_url.
    #
    # @param url [String] PostgreSQL connection URL with comma-separated hosts
    # @return [Hash] Sequel connection parameters
    def self.parse_postgres_multihost_url(url)
      opts = DatabaseConnection.parse_postgres_multihost_url(url)

      sequel_logger.info '[Database] Converted multi-host PostgreSQL URL to connection hash',
        host: opts[:host],
        port: opts[:port],
        database: opts[:database],
        has_user: opts.key?(:user),
        sslmode: opts[:sslmode]

      opts
    end

    def self.create_lazy_connection
      LazyConnection.new do
        sequel_logger.info '[Database] Creating Auth database connection'

        # Get database URL from auth config or environment
        database_url = Onetime.auth_config.database_url || 'sqlite://data/auth.db'

        connect(database_url)
      end
    end

    SQLITE_BUSY_TIMEOUT_MS = DatabaseConnection::SQLITE_BUSY_TIMEOUT_MS

    # Open an authdb connection with the application's SQL logger. Every
    # authdb connection is made here or, without the application loaded, in
    # Auth::DatabaseConnection.open, which holds the connection options and
    # documents the SQLite settings.
    #
    # A multi-host PostgreSQL URL is converted here first, for the log line.
    #
    # @param connection_opts [String, Hash] a database URL or a Sequel
    #   connection hash
    # @param logger [#info, nil] SQL logger; nil for the standalone migration
    #   path, which runs without the application loaded
    # @return [Sequel::Database]
    def self.connect(connection_opts, logger: Onetime.get_logger('Sequel'))
      connection_opts = parse_postgres_multihost_url(connection_opts) if DatabaseConnection.multihost_postgres_url?(connection_opts)

      DatabaseConnection.open(connection_opts, logger: logger)
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

        conn = connect(database_url, logger: nil)
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
