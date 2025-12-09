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
        @connector = connector
        @connection = nil
        @mutex = ::Mutex.new
      end

      def method_missing(method, *args, &block)
        __connection__.__send__(method, *args, &block)
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
      def is_a?(klass)
        __connection__.is_a?(klass)
      end

      def kind_of?(klass)
        __connection__.kind_of?(klass)
      end

      def instance_of?(klass)
        __connection__.instance_of?(klass)
      end

      def class
        __connection__.class
      end

      def disconnect
        @mutex.synchronize do
          @connection&.disconnect
          @connection = nil
        end
      end

      # Allow checking if connection has been established (useful for tests)
      def __connected__?
        @mutex.synchronize { !@connection.nil? }
      end

      # Force connection (useful for warmup)
      def __connect__!
        __connection__
        true
      end

      private

      def __connection__
        @mutex.synchronize do
          @connection ||= @connector.call
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

    # Check if a connection has been established
    def self.connected?
      return false unless @connection

      @connection.__connected__?
    end

    def self.create_lazy_connection
      LazyConnection.new do
        sequel_logger.info '[Database] Creating Auth database connection'

        # Get database URL from auth config or environment
        database_url = Onetime.auth_config.database_url || 'sqlite://data/auth.db'

        Sequel.connect(
          database_url,
          logger: Onetime.get_logger('Sequel'),
          sql_log_level: :trace,  # Log SQL statements at trace level for safety
        )
      end
    end

    # Legacy method for compatibility - creates connection immediately
    # Prefer using `connection` which returns a lazy proxy
    def self.create_connection
      sequel_logger.info '[Database] Creating Auth database connection (immediate)'

      database_url = Onetime.auth_config.database_url || 'sqlite://data/auth.db'

      Sequel.connect(
        database_url,
        logger: Onetime.get_logger('Sequel'),
        sql_log_level: :trace,
      )
    end
  end
end
