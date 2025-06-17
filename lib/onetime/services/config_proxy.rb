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
      # Uses merged config from ServiceRegistry which already prioritizes static over dynamic.
      #
      # @param key [Symbol, String] Configuration key
      # @return [Object] Configuration value or nil
      def [](key)
        key = key.to_s if key.respond_to?(:to_s)

        # Access merged config from ServiceRegistry
        merged_config = get_merged_config
        merged_config[key]
      end

      ##
      # Set configuration value.
      # This updates the merged config directly in ServiceRegistry.
      # Note: This doesn't persist to SystemSettings - use admin UI for persistent changes.
      #
      # @param key [Symbol, String] Configuration key
      # @param value [Object] Configuration value
      def []=(key, value)
        key = key.to_s if key.respond_to?(:to_s)

        # Update merged config with new value
        merged_config = get_merged_config.dup
        merged_config[key] = value
        Onetime::Services::ServiceRegistry.set_state(:merged_config, merged_config)
      end

      ##
      # Check if configuration key exists in merged config.
      #
      # @param key [Symbol, String] Configuration key
      # @return [Boolean] true if key exists
      def key?(key)
        key = key.to_s if key.respond_to?(:to_s)
        merged_config = get_merged_config
        merged_config.key?(key)
      end

      ##
      # Get all configuration keys from merged config.
      #
      # @return [Array<Symbol>] All available configuration keys
      def keys
        merged_config = get_merged_config
        merged_config.keys
      end

      ##
      # Get configuration as a hash.
      # Returns the merged configuration from ServiceRegistry.
      #
      # @return [Hash] Merged configuration hash
      def to_h
        get_merged_config
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
      def debug_dump
        merged_config = get_merged_config
        {
          static_keys: @static_config.keys.sort,
          merged_keys: merged_config.keys.sort,
          service_registry_available: service_registry_available?,
          has_merged_config: !merged_config.empty?,
        }
      end

      private

      ##
      # Get merged configuration from ServiceRegistry.
      # Falls back to static config if merged config is not available.
      #
      # @return [Hash] Merged configuration or static config as fallback
      def get_merged_config
        return @static_config unless service_registry_available?

        merged = Onetime::Services::ServiceRegistry.state(:merged_config)
        merged.nil? ? @static_config : merged
      rescue StandardError => ex
        # Log error but don't fail - graceful degradation
        OT.lw "[ConfigProxy] Error accessing merged config: #{ex.message}"
        @static_config
      end

      ##
      # Check if ServiceRegistry is available and ready for use.
      # Used to gracefully handle initialization ordering.
      #
      # @return [Boolean] true if ServiceRegistry is available
      def service_registry_available?
        defined?(Onetime::Services::ServiceRegistry) && Onetime::Services::ServiceRegistry.respond_to?(:state)
      end

      attr_reader :mutex
    end
  end
end
