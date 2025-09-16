# apps/api/v2/logic/colonel/get_system_settings.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetSystemSettings < V2::Logic::Base
        attr_reader :yaml_config

        def process_params
          # No parameters needed for GET operation
        end

        def raise_concerns; end

        def process
          @yaml_config = build_yaml_configuration

          OT.ld "[GetSystemSettings#process] Retrieved YAML-only system settings with #{@yaml_config.keys.size} sections"
        end

        def success_data
          {
            record: {}, # Always empty since we're not using Redis
            details: yaml_config,
          }
        end

        private

        # Build configuration directly from YAML, bypassing Redis entirely
        def build_yaml_configuration
          base_sections = SystemSettings.extract_system_settings(OT.conf)
          OT.ld "[GetSystemSettings#build_yaml_configuration] YAML-only sections: #{base_sections.keys}"

          base_sections
        end
      end
    end
  end
end
