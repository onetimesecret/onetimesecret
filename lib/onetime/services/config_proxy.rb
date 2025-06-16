# lib/onetime/services/config_proxy.rb

module Onetime
  module Services
    ##
    # Proxy class that provides unified access to both static and dynamic configuration.
    #
    # Static configuration comes from YAML files and takes precedence.
    # Dynamic configuration comes from Redis via ServiceRegistry state.
    #
    # This enables seamless access via OT.conf[:key] regardless of config source.
    #
    # @example Usage
    #   OT.conf[:storage]         # Static from YAML
    #   OT.conf[:user_interface]  # Dynamic from Redis
    #   OT.conf[:locales]         # Service state
    #
    class ConfigProxy
      def initialize(static_config)
        @static_config = static_config
        @mutex         = Mutex.new
      end

      ##
      # Access configuration value by key.
      # Static config takes precedence over dynamic config.
      #
      # @param key [Symbol, String] Configuration key
      # @return [Object] Configuration value or nil
      def [](key)
        key = key.to_sym if key.respond_to?(:to_sym)

        # Static config takes precedence to prevent dynamic overrides
        static_value = @static_config[key]
        return static_value unless static_value.nil?

        # Fall back to dynamic config from ServiceRegistry
        dynamic_value(key)
      end

      ##
      # Set configuration value.
      # Only allows setting dynamic values, not static config.
      #
      # @param key [Symbol, String] Configuration key
      # @param value [Object] Configuration value
      def []=(key, value)
        key = key.to_sym if key.respond_to?(:to_sym)

        # Prevent overriding static config
        if @static_config.key?(key)
          raise ArgumentError, "Cannot override static config key: #{key}"
        end

        ServiceRegistry.set_state(key, value)
      end

      ##
      # Check if configuration key exists in either static or dynamic config.
      #
      # @param key [Symbol, String] Configuration key
      # @return [Boolean] true if key exists
      def key?(key)
        key = key.to_sym if key.respond_to?(:to_sym)
        @static_config.key?(key) || dynamic_key?(key)
      end

      ##
      # Get all configuration keys from both static and dynamic sources.
      #
      # @return [Array<Symbol>] All available configuration keys
      def keys
        static_keys  = @static_config.keys
        dynamic_keys = dynamic_keys_safe
        (static_keys + dynamic_keys).uniq
      end

      ##
      # Get configuration as a hash.
      # Static config values override dynamic ones.
      #
      # @return [Hash] Combined configuration hash
      def to_h
        dynamic_hash = dynamic_config_safe
        dynamic_hash.merge(@static_config)
      end

      ##
      # Fetch configuration value with default.
      #
      # @param key [Symbol, String] Configuration key
      # @param default [Object] Default value if key not found
      # @return [Object] Configuration value or default
      def fetch(key, default = nil)
        value = self[key]
        value.nil? ? default : value
      end

      ##
      # Dig into nested configuration structures.
      #
      # @param keys [Array] Nested keys to traverse
      # @return [Object] Nested value or nil
      def dig(*keys)
        return nil if keys.empty?

        first_key = keys.first
        value     = self[first_key]

        return nil if value.nil?
        return value if keys.length == 1

        if value.respond_to?(:dig)
          value.dig(*keys[1..])
        end
      end

      ##
      # Reload static configuration.
      # Called when configuration is reloaded.
      #
      # @param new_static_config [Hash] New static configuration
      def reload_static(new_static_config)
        @mutex.synchronize do
          @static_config = new_static_config
        end
      end

      ##
      # Get debug information about configuration sources.
      #
      # @return [Hash] Debug information
      def debug_info
        {
          static_keys: @static_config.keys.sort,
          dynamic_keys: dynamic_keys_safe.sort,
          service_registry_available: service_registry_available?,
        }
      end

      private

      ##
      # Safely get dynamic configuration value from ServiceRegistry.
      # Returns nil if ServiceRegistry is not available or key doesn't exist.
      #
      # @param key [Symbol] Configuration key
      # @return [Object] Dynamic configuration value or nil
      def dynamic_value(key)
        return nil unless service_registry_available?

        ServiceRegistry.state(key)
      rescue StandardError => ex
        # Log error but don't fail - graceful degradation
        OT.lw "[ConfigProxy] Error accessing dynamic config: #{ex.message}"
        nil
      end

      ##
      # Check if key exists in dynamic configuration.
      # Returns false if ServiceRegistry is not available.
      #
      # @param key [Symbol] Configuration key
      # @return [Boolean] true if key exists in dynamic config
      def dynamic_key?(key)
        return false unless service_registry_available?

        !ServiceRegistry.state(key).nil?
      rescue StandardError
        false
      end

      ##
      # Safely get all dynamic configuration keys.
      # Returns empty array if ServiceRegistry is not available.
      #
      # @return [Array<Symbol>] Dynamic configuration keys
      def dynamic_keys_safe
        return [] unless service_registry_available?

        # ServiceRegistry doesn't expose keys directly, so we can't enumerate them
        # This is a limitation - we only know about keys we explicitly ask for
        []
      rescue StandardError
        []
      end

      ##
      # Safely get full dynamic configuration as hash.
      # Returns empty hash if ServiceRegistry is not available.
      #
      # @return [Hash] Dynamic configuration hash
      def dynamic_config_safe
        return {} unless service_registry_available?

        # ServiceRegistry doesn't expose all state as hash
        # This is intentional - dynamic config should be accessed key-by-key
        {}
      rescue StandardError
        {}
      end

      ##
      # Check if ServiceRegistry is available and ready for use.
      # Used to gracefully handle initialization ordering.
      #
      # @return [Boolean] true if ServiceRegistry is available
      def service_registry_available?
        defined?(ServiceRegistry) && ServiceRegistry.respond_to?(:state)
      end

      attr_reader :mutex
    end
  end
end
