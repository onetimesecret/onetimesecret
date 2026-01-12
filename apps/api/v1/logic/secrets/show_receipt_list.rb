# apps/api/v1/logic/secrets/show_receipt_list.rb
#
# frozen_string_literal: true

require 'time'

module V1::Logic
  module Secrets

    class ShowReceiptList < V1::Logic::Base
      # NOTE: Controller calls `logic.receipts` for this list of receipts
      attr_reader :receipts, :since, :now, :query_results
      attr_reader :received, :notreceived, :has_items

      def process_params
        # Calculate the timestamp for 30 days ago
        @now = Time.now
        @since = (Time.now - 30*24*60*60).to_i
      end

      def raise_concerns
        # No specific concerns for listing receipts
      end

      def process
        # Fetch entries from the sorted set within the past 30 days
        @query_results = cust.receipts.rangebyscore(since, @now.to_i)

        # Get the safe fields for each record
        @receipts = query_results.filter_map do |identifier|
          md = Onetime::Receipt.find_by_identifier(identifier)
          md&.safe_dump
        end

        @has_items = receipts.any?
        @received, @notreceived = *receipts.partition{ |m| m[:is_destroyed] }
        received.sort_by! { |a| a[:updated] }
        notreceived.sort!{ |a,b| b[:updated] <=> a[:updated] }
      end

      def success_data
        {
          custid: cust.custid,
          count: receipts.count,
          records: receipts,
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
