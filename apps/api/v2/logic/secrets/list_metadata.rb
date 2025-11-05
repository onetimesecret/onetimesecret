# apps/api/v2/logic/secrets/list_metadata.rb

require 'time'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ListMetadata < V2::Logic::Base
      attr_reader :records, :since, :now, :query_results, :received, :notreceived, :has_items

      def process_params
        # Calculate the timestamp for 30 days ago
        @now   = Familia.now
        @since = (Familia.now - (30 * 24 * 60 * 60)).to_i
      end

      def raise_concerns; end

      def process
        # Fetch entries from the sorted set within the past 30 days
        @query_results = cust.metadata.rangebyscore(since, @now.to_i)

        # Get the safe fields for each record
        @records = query_results.filter_map do |identifier|
          md = Onetime::Metadata.find_by_identifier(identifier)
          md&.safe_dump
        end

        @has_items              = records.any?
        records.sort! { |a, b| b[:updated] <=> a[:updated] }
        @received, @notreceived = *records.partition { |m| m[:is_destroyed] }

        success_data
      end

      def success_data
        {
          'custid' => cust.custid,
          'count' => records.count,
          'records' => records,
          'details' => {
            'type' => 'list', # Add the type discriminator
            'since' => since,
            'now' => now,
            'has_items' => has_items,
            'received' => received,
            'notreceived' => notreceived,
          },
        }
      end
    end
  end
end
