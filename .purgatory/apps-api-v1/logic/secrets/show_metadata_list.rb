# apps/api/v1/logic/secrets/show_metadata_list.rb
#
# frozen_string_literal: true

require 'time'

module V1::Logic
  module Secrets

    using Familia::Refinements::TimeLiterals

    class ShowMetadataList < V1::Logic::Base
      attr_reader :records, :since, :now, :query_results
      attr_reader :received, :notreceived, :has_items

Familia

      def raise_concerns

      end

      def process
        # Fetch entries from the sorted set within the past 30 days
        @query_results = cust.metadata.rangebyscore(since, @now.to_i)

        # Get the safe fields for each record
        @records = query_results.filter_map do |identifier|
          md = V1::Metadata.find_by_identifier(identifier)
          md&.safe_dump
        end

        @has_items = records.any?
        @received, @notreceived = *records.partition{ |m| m[:is_destroyed] }
        received.sort_by! { |a| a[:updated] }
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
            notreceived: notreceived,
          },
        }
      end
    end

  end
end
