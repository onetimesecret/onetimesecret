require 'time'

module Onetime::Logic
  module Secrets

    class ShowMetadataList < OT::Logic::Base
      attr_reader :records, :since, :now, :query_results

      def process_params
        # Calculate the timestamp for 30 days ago
        @now = Time.now
        @since = (Time.now - 30*24*60*60).to_i

      end

      def raise_concerns
        limit_action :show_metadata
        raise OT::MissingSecret if metadata.nil?
      end

      def process
        # Fetch entries from the sorted set within the past 30 days
        @query_results = cust.metadata_list.rangebyscore(thirty_days_ago, @now.to_i)

        # Get the safe fields for each record
        @records = query_results.transform_values do |metadata|
          metadata.safe_fields
        end
      end

      def success_data
        {
          custid: cust.custid,
          count: records.count,
          records: records,
          details: {
            since: since,
            now: now
          }
        }
      end
    end

  end
end
