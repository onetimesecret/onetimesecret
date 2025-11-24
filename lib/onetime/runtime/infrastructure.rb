# lib/onetime/runtime/infrastructure.rb
#
# frozen_string_literal: true

module Onetime
  module Runtime
    # Infrastructure runtime state
    #
    # Holds database connections, logging infrastructure, and diagnostics
    # configuration set during boot. This state is immutable after
    # initialization and thread-safe.
    #
    # Set by: SetupConnectionPool, SetupLoggers, SetupDiagnostics initializers
    #
    Infrastructure = Data.define(
      :database_pool,      # ConnectionPool for Redis/Valkey connections
      :cached_loggers,     # Hash of cached SemanticLogger instances
      :d9s_enabled,        # Whether diagnostics (Sentry) is enabled
    ) do
      # Factory method for default state
      #
      # @return [Infrastructure] Infrastructure state with safe defaults
      #
      def self.default
        new(
          database_pool: nil,
          cached_loggers: {},
          d9s_enabled: false,
        )
      end

      # Check if database pool is configured
      #
      # @return [Boolean] true if database pool exists
      #
      def database_configured?
        !database_pool.nil?
      end

      # Check if diagnostics are enabled
      #
      # @return [Boolean] true if Sentry/diagnostics enabled
      #
      def diagnostics_enabled?
        d9s_enabled
      end

      # Get logger for a specific category
      #
      # @param category [String, Symbol] Logger category
      # @return [SemanticLogger::Logger, nil] Logger instance or nil
      #
      def logger(category)
        cached_loggers[category.to_s]
      end
    end
  end
end
