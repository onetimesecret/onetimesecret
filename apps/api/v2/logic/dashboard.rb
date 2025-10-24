# apps/api/v2/logic/dashboard.rb

require_relative 'base'

module V2
  module Logic
    module Dashboard
      class Index < V2::Logic::Base
        def process_params; end

        def raise_concerns; end

        def process = success_data
      end

      # FYI: this class is used by v1 API
      class ShowRecentMetadata < V2::Logic::Base
        attr_reader :metadata

        def process_params
          @metadata = cust.metadata_list
        end

        def raise_concerns
          raise V2::MissingSecret if metadata.nil?
        end

        def process = success_data
      end
    end
  end
end
