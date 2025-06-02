# apps/api/v2/logic/colonel/get_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetColonelSettings < V2::Logic::Base
        attr_reader :current_record, :merged_config

        def process_params
          # No parameters needed for GET operation
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          @current_record = fetch_current_colonel_config
          @merged_config = build_merged_configuration

          OT.ld "[GetColonelSettings#process] Retrieved colonel config with #{@merged_config.keys.size} sections"
        end

        def success_data
          {
            record: current_record&.safe_dump || {},
            details: merged_config,
          }
        end

        private

        # Safely fetch the current colonel config, handling the case where none exists
        def fetch_current_colonel_config
          ColonelSettings.current
        rescue Onetime::RecordNotFound
          OT.ld "[GetColonelSettings#fetch_current_colonel_config] No colonel config found, using base config only"
          nil
        end

        # Build configuration by directly merging colonel overrides with base sections
        def build_merged_configuration
          base_sections = ColonelSettings.extract_colonel_config(OT.conf)
          OT.ld "[GetColonelSettings#build_merged_configuration] Base sections: #{base_sections.keys}"

          return base_sections unless current_record

          # Get the colonel overrides directly (with proper deserialization)
          colonel_overrides = current_record.filtered
          OT.ld "[GetColonelSettings#build_merged_configuration] Colonel overrides (raw): #{colonel_overrides}"

          # Merge colonel overrides directly into base sections
          merged = Onetime::Config.deep_merge(base_sections, colonel_overrides)
          OT.ld "[GetColonelSettings#build_merged_configuration] Final merged result: #{merged}"

          merged
        end
      end
    end
  end
end
