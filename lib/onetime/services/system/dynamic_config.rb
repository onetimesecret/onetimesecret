# lib/onetime/services/system/dynamic_config.rb

require_relative '../service_provider'

# Load SystemSettings model for dynamic configuration
require_relative '../../../../apps/api/v2/models/system_settings'

module Onetime
  module Services
    module System
      ##
      # Dynamic Configuration Provider
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
      class DynamicConfig < ServiceProvider
        # No default config needed - SystemSettings handles defaults internally

        def initialize
          super(:dynamic_config, type: TYPE_CONFIG, priority: 10) # High priority - load early
        end

        ##
        # Merge static and dynamic configuration and store in ServiceRegistry
        #
        # @param config [Hash] Static configuration
        def start(config)
          log('Merging static and dynamic configuration...')

          # Merge static config with dynamic SystemSettings
          merged_config = merge_static_and_dynamic_config(config)

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
          dynamic_config   = current_settings.to_onetime_config

          # Deep merge dynamic config over static config
          merged = deep_merge(base_config, dynamic_config)

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
        # Deep merge two configuration hashes
        #
        # @param base [Hash] Base configuration
        # @param overlay [Hash] Configuration to merge over base
        # @return [Hash] Merged configuration
        def deep_merge(base, overlay)
          base.merge(overlay) do |_key, base_val, overlay_val|
            if base_val.is_a?(Hash) && overlay_val.is_a?(Hash)
              deep_merge(base_val, overlay_val)
            else
              overlay_val
            end
          end
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
