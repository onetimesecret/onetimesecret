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
    # UNDERSTANDING OT.conf vs OT.state:
    #
    # OT.conf - Unified configuration access (THIS CLASS)
    # - Provides merged view of static YAML + dynamic Redis config
    # - Read-only interface to configuration values
    # - Examples: OT.conf[:storage], OT.conf[:mail], OT.conf[:ui]
    # - Automatically falls back to static config if dynamic unavailable
    #
    # OT.state - Direct ServiceRegistry state access
    # - Raw access to runtime state and computed values
    # - Used internally by service providers
    # - Examples: OT.state[:locales], OT.state[:emailer_configured]
    # - No fallback - returns nil if key doesn't exist
    #
    # For application code, use OT.conf for all configuration needs.
    # Only use OT.state when you specifically need runtime state values
    # that aren't part of configuration (e.g., processed locale data).
    #
    # @example Usage
    #   OT.conf[:storage]         # Static from YAML
    #   OT.conf[:ui][:theme]      # Dynamic from Redis
    #   OT.conf[:mail][:provider] # Merged config
    #
    class ConfigProxy

      def initialize(static_config)
        @static_config = static_config
        @mutex         = Mutex.new
      end

      # Provide a way to access the static configuration directly.
      #
      # We generally prefer to avoid doing accessing the static config directly
      # but there are good reasons to sometimes (e.g. ease of debugging is a
      # great example, also testabilty, and code that works exclusively with
      # the static config). By offering an official way to do it, we can more
      # readily understand code that uses it.
      #
      # e.g. OT.conf.static['site']['host']
      #
      def static
        @static_config
      end

      ##
      # Access configuration value by key.
      # Uses merged config from ServiceRegistry which already prioritizes static over dynamic.
      #
      # @param key [Symbol, String] Configuration key
      # @return [Object] Configuration value or nil
      def [](key)
        fetch(key)
      rescue KeyError
        nil
      end

      ##
      # Check if configuration key exists in merged config.
      #
      # @param key [Symbol, String] Configuration key
      # @return [Boolean] true if key exists
      def key?(key)
        key = key.to_s if key.respond_to?(:to_s)
        get_runtime_config.key?(key)
      end

      ##
      # Get all configuration keys from merged config.
      #
      # @return [Array<Symbol>] All available configuration keys
      def keys
        get_runtime_config.keys
      end

      ##
      # Get configuration as a hash.
      # Returns the merged configuration from ServiceRegistry.
      #
      # @return [Hash] Merged configuration hash
      def to_h
        get_runtime_config.to_h
      end

      ##
      # Fetch configuration value with default.
      #
      # @param key [Symbol, String] Configuration key
      # @param default [Object] Default value if key not found
      # @return [Object] Configuration value or default
      def fetch(key, default = nil)
        return default if key.nil?

        # Originally this was the plan for ConfigProxy: to check the static
        # config first followed by the dynamic config. The idea was to prevent
        # accidentally clobbering the static config with dynamic config values.
        #
        # But there is a big drawback: it means that there is no one source of
        # truth for configuration, except for the Ruby process' memory. Merging
        # takes a bit of work and needs to be done in a mindful way so that
        # we aren't constantly merging. The merged config functions like a
        # cache as well. Unless the dynamic config is being modified in the
        # colonel, there doesn't need to be anhy merging going on at all.
        #
        # val = @static_config[key] || Onetime::Services::ServiceRegistry.state[key]

        val = get_runtime_config[key.to_s]
        val.nil? ? default : val
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
        runtime_config = get_runtime_config
        {
          static_keys: @static_config.keys.sort,
          merged_keys: runtime_config.keys.sort,
          service_registry_available: service_registry_available?,
          has_runtime_config: !runtime_config.empty?,
        }
      end

      private

      ##
      # Get merged configuration from ServiceRegistry.
      # Falls back to static config if merged config is not available.
      #
      # TODO: The get_runtime_config method catches all StandardError
      # exceptions and falls back to static config, which might mask
      # important configuration errors. Consider more specific exception
      # handling or at least logging the specific error types. #1497
      #
      # @return [Hash] Merged configuration or static config as fallback
      def get_runtime_config
        return @static_config unless service_registry_available?

        merged = Onetime::Services::ServiceRegistry.state['runtime_config']
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
