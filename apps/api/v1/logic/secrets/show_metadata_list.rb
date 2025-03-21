# apps/api/v1/logic/secrets/show_metadata_list.rb

require 'time'

module V1::Logic
  module Secrets

    class ShowMetadataList < V1::Logic::Base
      attr_reader :records, :since, :now, :query_results
      attr_reader :received, :notreceived, :has_items

      def process_params
        # Calculate the timestamp for 30 days ago
        @now = Time.now
        @since = (Time.now - 30*24*60*60).to_i

      end

      def raise_concerns
        limit_action :show_metadata
      end

      def process
        # Fetch entries from the sorted set within the past 30 days
        @query_results = cust.metadata.rangebyscore(since, @now.to_i)

        # Get the safe fields for each record
        @records = query_results.filter_map do |identifier|
          md = OT::Metadata.from_identifier(identifier)
          md&.safe_dump
        end

        @has_items = records.any?
        @received, @notreceived = *records.partition{ |m| m[:is_destroyed] }
        received.sort!{ |a,b| a[:updated] <=> b[:updated] }
        notreceived.sort!{ |a,b| b[:updated] <=> a[:updated] }
      end

      def success_data
        {
          custid: cust.custid,
          count: records.count,
          records: records,
          details: {
            type: 'list', # Add the type discriminator
            since: since,
            now: now,
            has_items: has_items,
            received: received,
            notreceived: notreceived
          }
        }
      end
    end

  end
end
