# apps/api/v2/logic/colonel/get_mutable_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetMutableConfig < V2::Logic::Base
        attr_reader :current_record, :runtime_config

        def process_params
          # No parameters needed for GET operation
        end

        def raise_concerns
          limit_action :view_colonel
        end

        def process
          @current_record = fetch_current_mutable_config
          @runtime_config  = build_runtime_configuration

          OT.ld "[GetMutableConfig#process] Retrieved mutable config with #{@runtime_config.keys.size} sections"
        end

        def success_data
          {
            record: current_record&.safe_dump || {},
            details: runtime_config,
          }
        end

        private

        # Safely fetch the current mutable config, handling the case where none exists
        def fetch_current_mutable_config
          MutableConfig.current
        rescue Onetime::RecordNotFound
          OT.ld '[GetMutableConfig#fetch_current_mutable_config] No mutable config found, using base config only'
          nil
        end

        # Build configuration by directly merging colonel overrides with base sections
        def build_runtime_configuration
          base_sections = MutableConfig.extract_mutable_config(OT.conf)
          OT.ld "[GetMutableConfig#build_runtime_configuration] Base sections: #{base_sections.keys}"

          return base_sections unless current_record

          # Get the colonel overrides directly (with proper deserialization)
          colonel_overrides = current_record.filtered
          OT.ld "[GetMutableConfig#build_runtime_configuration] Colonel overrides (raw): #{colonel_overrides}"

          # Merge colonel overrides directly into base sections
          merged = OT::Configurator.deep_merge(base_sections, colonel_overrides)
          OT.ld "[GetMutableConfig#build_runtime_configuration] Final merged result: #{merged}"

          merged
        end
      end
    end
  end
end
