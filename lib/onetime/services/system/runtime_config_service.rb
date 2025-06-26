# lib/onetime/services/system/runtime_config_service.rb

require_relative '../service_provider'

# Load MutableConfig model for dynamic configuration
require 'v2/models/mutable_config'

module Onetime
  module Services
    module System
      ##
      # Runtime Configuration Service Provider
      #
      # Merges static configuration with dynamic MutableConfig from Redis
      # and makes the merged result available through ServiceRegistry.
      # This provider runs early in the service startup sequence so other
      # providers can access the unified configuration.
      #
      # Dynamic settings managed by MutableConfig:
      # - Interface configuration (branding, footer links)
      # - Secret options (TTL settings)
      # - Mail configuration
      # - Rate limits
      # - Diagnostics settings
      #
      class RuntimeConfigService < ServiceProvider
        # No default config needed - MutableConfig handles defaults internally

        def initialize
          # High priority - load early
          super(:runtime_config, type: TYPE_CONFIG, priority: 10)
        end

        ##
        # Merge static and dynamic configuration and store in ServiceRegistry
        #
        # @param config [Hash] Static configuration
        def start(config)
          @config = config

          debug('Checking for existing merged configuration...')
          runtime_config = get_state(:runtime_config)

          unless runtime_config.nil?
            return debug('Existing merged configuration found, exiting early')
          end

          debug('Fetching MutableConfig from Redis.')
          # Merge static config with dynamic MutableConfig
          runtime_config = merge_static_and_dynamic_config(config)

          # TOOD: Anything going in to set_state should be deep frozen
          # automatically. There are too many changes going on at the
          # moment to switch now but it conceivably could be done.
          OT::Utils.deep_freeze(runtime_config)

          # Store merged config in ServiceRegistry for unified access
          set_state(:runtime_config, runtime_config)

          debug('Configuration merge completed successfully')
        end

        ##
        # Reload and re-merge configuration (for hot reload capability)
        #
        # @param new_config [Hash] New static configuration
        def reload(new_config)
          log('Reloading and re-merging configuration...')
          start(new_config)
        end

        ##
        # Health check - verify MutableConfig accessibility
        #
        # @return [Boolean] true if MutableConfig is accessible
        def healthy?
          super && redis_available?
        end

        private

        ##
        # Merge static configuration with dynamic MutableConfig
        #
        # @param static_config [Hash] Static configuration from YAML
        # @return [Hash] Merged configuration
        def merge_static_and_dynamic_config(static_config)
          base_config = static_config.dup

          # Load current MutableConfig and convert to Onetime config format
          current_settings = V2::MutableConfig.current
          dynamic_config   = current_settings.safe_dump

          # Deep merge dynamic config over static config
          merged = OT::Utils.deep_merge(base_config, dynamic_config)

          debug("Merged #{dynamic_config.keys.size} dynamic config sections")
          merged
        rescue Onetime::RecordNotFound
          log('No MutableConfig found, using static configuration only')
          base_config
        rescue StandardError => ex
          error("Failed to load MutableConfig: #{ex.message}")
          log('Falling back to static configuration only')
          base_config
        end

        ##
        # Check if MutableConfig is available
        #
        # @return [Boolean] true if MutableConfig is accessible
        def mutable_config_available?
          defined?(V2::MutableConfig) && V2::MutableConfig.respond_to?(:current)
        end

        ##
        # Check if Redis is available for MutableConfig operations
        #
        # @return [Boolean] true if Redis is accessible
        def redis_available?
          return false unless mutable_config_available?

          # Try to access MutableConfig to test Redis connectivity
          V2::MutableConfig.current
          true
        rescue Onetime::RecordNotFound
          # No current settings is fine - Redis is available
          true
        rescue StandardError => ex
          debug("Redis unavailable: #{ex.message}")
          false
        end
      end
    end
  end
end
