# apps/api/v2/logic/colonel/get_colonel_config.rb

require_relative '../base'

module V2
  module Logic
    module Colonel
      class GetColonelConfig < V2::Logic::Base
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

          OT.ld "[GetColonelConfig#process] Retrieved colonel config with #{@merged_config.keys.size} sections"
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
          ColonelConfig.current
        rescue Onetime::RecordNotFound
          OT.ld "[GetColonelConfig#fetch_current_colonel_config] No colonel config found, using base config only"
          nil
        end

        # Build configuration using existing config merge functionality
        def build_merged_configuration
          base_sections = ColonelConfig.extract_colonel_config(OT.conf)

          return base_sections unless current_record

          colonel_overrides = ColonelConfig.construct_onetime_config(current_record)
          Onetime::Config.deep_merge(base_sections, colonel_overrides)
        end
      end
    end
  end
end
