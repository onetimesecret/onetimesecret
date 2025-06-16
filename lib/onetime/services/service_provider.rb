# lib/onetime/services/service_provider.rb

require 'concurrent'
require_relative 'service_registry'

module Onetime
  module Services
    ##
    # Base class for service providers in the two-phase initialization system.
    #
    # Service providers run in Phase 2 (after config freeze) to initialize
    # services, manage runtime state, and load dynamic configuration.
    #
    # Provider Types:
    # - Instance: Returns service objects (e.g., LocaleService instance)
    # - Connection: Configures modules (e.g., EmailerService sets up mailer)
    # - Config: Loads dynamic settings into ServiceRegistry state
    #
    # @example Instance Provider
    #   class LocaleProvider < ServiceProvider
    #     def start(config)
    #       locale_service = LocaleService.new(config[:locales])
    #       register_instance(:locales, locale_service)
    #     end
    #   end
    #
    # @example Connection Provider
    #   class DatabaseProvider < ServiceProvider
    #     def start(config)
    #       setup_database_connection(config[:database_url])
    #       register_connection(:database, :ready)
    #     end
    #   end
    #
    # @example Config Provider
    #   class DynamicConfigProvider < ServiceProvider
    #     def start(config)
    #       redis_settings = load_from_redis()
    #       redis_settings.each { |k, v| set_state(k, v) }
    #     end
    #   end
    #
    class ServiceProvider
      attr_reader :name, :status, :config, :dependencies, :priority

      # Provider lifecycle states
      STATUS_PENDING  = :pending
      STATUS_STARTING = :starting
      STATUS_RUNNING  = :running
      STATUS_STOPPING = :stopping
      STATUS_STOPPED  = :stopped
      STATUS_ERROR    = :error

      # Provider types
      TYPE_INSTANCE   = :instance
      TYPE_CONNECTION = :connection
      TYPE_CONFIG     = :config

      def initialize(name, type: TYPE_INSTANCE, dependencies: [], priority: 50)
        @name         = name.to_sym
        @type         = type.to_sym
        @dependencies = dependencies.map(&:to_sym)
        @priority     = priority
        @status       = STATUS_PENDING
        @config       = nil
        @mutex        = Mutex.new
        @error        = nil
      end

      ##
      # Start the service provider with given configuration.
      # Subclasses must implement this method.
      #
      # @param config [Hash] Frozen configuration hash
      # @raise [NotImplementedError] if not overridden by subclass
      def start(config)
        raise NotImplementedError, "#{self.class}#start must be implemented"
      end

      ##
      # Stop the service provider and clean up resources.
      # Default implementation does nothing; override if cleanup needed.
      #
      def stop
        # Override in subclasses that need cleanup
      end

      ##
      # Reload the service provider with new configuration.
      # Default implementation stops and restarts; override for hot reload.
      #
      # @param new_config [Hash] New configuration hash
      def reload(new_config)
        stop
        start_internal(new_config)
      end

      ##
      # Check if provider is healthy and operational.
      # Override in subclasses for custom health checks.
      #
      # @return [Boolean] true if healthy, false otherwise
      def healthy?
        @status == STATUS_RUNNING && @error.nil?
      end

      ##
      # Get provider status information for monitoring.
      #
      # @return [Hash] Status information
      def status_info
        {
          name: @name,
          type: @type,
          status: @status,
          dependencies: @dependencies,
          priority: @priority,
          error: @error&.message,
          healthy: healthy?,
        }
      end

      ##
      # Start the provider with proper lifecycle management.
      # Called by orchestration system; don't call directly.
      #
      # @param config [Hash] Configuration to use
      def start_internal(config)
        @mutex.synchronize do
          return if @status == STATUS_RUNNING

          @status = STATUS_STARTING
          @config = config
          @error  = nil

          begin
            start(config)
            @status = STATUS_RUNNING
            OT.li "[ServiceProvider] Started #{@name} (#{@type})"
          rescue StandardError => ex
            @status = STATUS_ERROR
            @error  = ex
            OT.le "[ServiceProvider] Failed to start #{@name}: #{ex.message}"
            raise
          end
        end
      end

      ##
      # Stop the provider with proper lifecycle management.
      # Called by orchestration system; don't call directly.
      #
      def stop_internal
        @mutex.synchronize do
          return if @status == STATUS_STOPPED

          @status = STATUS_STOPPING

          begin
            stop
            @status = STATUS_STOPPED
            OT.li "[ServiceProvider] Stopped #{@name}"
          rescue StandardError => ex
            @status = STATUS_ERROR
            @error  = ex
            OT.le "[ServiceProvider] Error stopping #{@name}: #{ex.message}"
            raise
          end
        end
      end

      protected

      ##
      # Register an instance provider with ServiceRegistry.
      # Used by instance-type providers that return service objects.
      #
      # @param key [Symbol] Registry key
      # @param instance [Object] Service instance to register
      def register_instance(key, instance)
        Onetime::Services::ServiceRegistry.register(key, instance)
      end

      ##
      # Register a connection provider with ServiceRegistry.
      # Used by connection-type providers that configure modules.
      #
      # @param key [Symbol] Registry key
      # @param status [Object] Connection status/info
      def register_connection(key, status)
        Onetime::Services::ServiceRegistry.register(key, status)
      end

      ##
      # Set dynamic state in ServiceRegistry.
      # Used by config-type providers for dynamic configuration.
      #
      # @param key [Symbol] State key
      # @param value [Object] State value
      def set_state(key, value)
        Onetime::Services::ServiceRegistry.set_state(key, value)
      end

      ##
      # Get dynamic state from ServiceRegistry.
      #
      # @param key [Symbol] State key
      # @return [Object] State value or nil
      def get_state(key)
        Onetime::Services::ServiceRegistry.state(key)
      end

      ##
      # Access frozen configuration passed to start().
      #
      # @param key [Symbol] Configuration key
      # @return [Object] Configuration value
      def conf(key)
        @config&.dig(key)
      end

      ##
      # Log provider-specific messages with context.
      #
      # @param message [String] Log message
      def log(message)
        OT.li "[#{@name}] #{message}"
      end

      def error(message)
        OT.le "[#{@name}] #{message}"
      end

      def debug(message)
        OT.ld "[#{@name}] #{message}"
      end

      private

      attr_reader :mutex
    end
  end
end
