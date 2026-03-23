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
        # Use Familia.now for consistency with receipt scores (float timestamps)
        @now = Familia.now
        @since = (Familia.now - 30*24*60*60).to_i
      end

      def raise_concerns
        # No specific concerns for listing receipts
      end

      def process
        # Fetch entries from the sorted set within the past 30 days
        # NOTE: Use @now (float) not @now.to_i - receipts are added with float scores
        # and truncating to int excludes receipts added in the same second
        @query_results = cust.receipts.rangebyscore(since, @now)

        # Return Receipt model objects (not safe_dump hashes) because the V1
        # controller passes these to receipt_hsh which needs model methods
        # like secret_ttl, identifier, current_expiration, and to_h.
        @receipts = query_results.filter_map do |identifier|
          Onetime::Receipt.find_by_identifier(identifier)
        end

        @has_items = receipts.any?
        @received, @notreceived = *receipts.partition { |m|
          m.state?(:revealed) || m.state?(:received) ||
            m.state?(:burned) || m.state?(:expired) || m.state?(:orphaned)
        }
        received.sort_by! { |a| a.updated.to_i }
        notreceived.sort! { |a, b| b.updated.to_i <=> a.updated.to_i }
      end

      def success_data
        {
          custid: cust.custid,
          count: receipts.count,
          records: receipts.map(&:safe_dump),
          details: {
            type: 'list', # Add the type discriminator
            since: since,
            now: now,
            has_items: has_items,
            revealed_receipts: received.map(&:safe_dump),
            pending_receipts: notreceived.map(&:safe_dump),
          },
        }
      end
    end

  end
end
