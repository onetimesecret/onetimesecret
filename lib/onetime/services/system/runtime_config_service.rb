# lib/onetime/services/system/runtime_config_service.rb

require_relative '../service_provider'

# Load SystemSettings model for dynamic configuration
require 'v2/models/system_settings'

module Onetime
  module Services
    module System
      ##
      # Runtime Configuration Service Provider
      #
      # Merges static configuration with dynamic SystemSettings from Redis
      # and makes the merged result available through ServiceRegistry.
      # This provider runs early in the service startup sequence so other
      # providers can access the unified configuration.
      #
      # Dynamic settings managed by SystemSettings:
      # - Interface configuration (branding, footer links)
      # - Secret options (TTL settings)
      # - Mail configuration
      # - Rate limits
      # - Diagnostics settings
      #
      class RuntimeConfigService < ServiceProvider
        # No default config needed - SystemSettings handles defaults internally

        def initialize
          # High priority - load early
          super(:dynamic_config, type: TYPE_CONFIG, priority: 10)
        end

        ##
        # Merge static and dynamic configuration and store in ServiceRegistry
        #
        # @param config [Hash] Static configuration
        def start(config)
          @config = config

          log('Checking for existing merged configuration...')
          merged_config = get_state(:merged_config)

          unless merged_config.nil?
            return warn('Existing merged configuration found, exiting early')
          end

          log('Fetching SystemSettings from Redis.')
          # Merge static config with dynamic SystemSettings
          merged_config = merge_static_and_dynamic_config(config)

          # TOOD: Anything going in to set_state should be deep frozen
          # automatically. There are too many changes going on at the
          # moment to switch now but it conceivably could be done.
          OT::Utils.deep_freeze(merged_config)

          # Store merged config in ServiceRegistry for unified access
          set_state(:merged_config, merged_config)

          log('Configuration merge completed successfully')
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
        # Health check - verify SystemSettings accessibility
        #
        # @return [Boolean] true if SystemSettings is accessible
        def healthy?
          super && system_settings_available?
        end

        private

        ##
        # Merge static configuration with dynamic SystemSettings
        #
        # @param static_config [Hash] Static configuration from YAML
        # @return [Hash] Merged configuration
        def merge_static_and_dynamic_config(static_config)
          base_config = static_config.dup

          # Load current SystemSettings and convert to Onetime config format
          current_settings = V2::SystemSettings.current
          dynamic_config   = current_settings.safe_dump

          # Deep merge dynamic config over static config
          merged = OT::Utils.deep_merge(base_config, dynamic_config)

          debug("Merged #{dynamic_config.keys.size} dynamic config sections")
          merged
        rescue Onetime::RecordNotFound
          log('No SystemSettings found, using static configuration only')
          base_config
        rescue StandardError => ex
          error("Failed to load SystemSettings: #{ex.message}")
          log('Falling back to static configuration only')
          base_config
        end

        ##
        # Check if SystemSettings is available
        #
        # @return [Boolean] true if SystemSettings is accessible
        def system_settings_available?
          defined?(V2::SystemSettings) && V2::SystemSettings.respond_to?(:current)
        end
      end
    end
  end
end
