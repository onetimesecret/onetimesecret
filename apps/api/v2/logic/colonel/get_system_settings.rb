# apps/api/v2/logic/colonel/get_system_settings.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetSystemSettings < V2::Logic::Base
        attr_reader :current_record, :merged_config

        def process_params
          # No parameters needed for GET operation
        end

        def raise_concerns; end

        def process
          @current_record = fetch_current_system_settings
          @merged_config = build_merged_configuration

          OT.ld "[GetSystemSettings#process] Retrieved system settings with #{@merged_config.keys.size} sections"
        end

        def success_data
          {
            record: current_record&.safe_dump || {},
            details: merged_config,
          }
        end

        private

        # Safely fetch the current system settings, handling the case where none exists
        def fetch_current_system_settings
          SystemSettings.current
        rescue Onetime::RecordNotFound
          OT.ld '[GetSystemSettings#fetch_current_system_settings] No system settings found, using base config only'
          nil
        end

        # Build configuration by directly merging colonel overrides with base sections
        def build_merged_configuration
          base_sections = SystemSettings.extract_system_settings(OT.conf)
          OT.ld "[GetSystemSettings#build_merged_configuration] Base sections: #{base_sections.keys}"

          return base_sections unless current_record

          # Get the colonel overrides directly (with proper deserialization)
          colonel_overrides = current_record.filtered
          OT.ld "[GetSystemSettings#build_merged_configuration] Colonel overrides (raw): #{colonel_overrides}"

          # Merge colonel overrides directly into base sections
          merged = Onetime::Config.deep_merge(base_sections, colonel_overrides)
          OT.ld "[GetSystemSettings#build_merged_configuration] Final merged result: #{merged}"

          merged
        end
      end
    end
  end
end
