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

          OT.ld "[GetMutableConfig#process] Retrieved mutable config with #{@current_record.keys.size} sections"
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

      end
    end
  end
end
