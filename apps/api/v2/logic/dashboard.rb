
require_relative 'base'

module Onetime::Logic
  module Dashboard

    class Index < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        limit_action :dashboard
      end
      def process
      end
    end

    # FYI: this class is used by v1 API
    class ShowRecentMetadata < OT::Logic::Base
      attr_reader :metadata
      def process_params
        @metadata = cust.metadata_list
      end
      def raise_concerns
        limit_action :show_metadata
        raise OT::MissingSecret if metadata.nil?
      end
      def process
      end
    end

  end
end
