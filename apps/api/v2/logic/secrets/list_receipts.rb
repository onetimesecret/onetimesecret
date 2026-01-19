# apps/api/v2/logic/secrets/list_receipts.rb
#
# frozen_string_literal: true

require 'time'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ListReceipts < V2::Logic::Base
      attr_reader :records, :since, :now, :query_results, :received, :notreceived, :has_items

      def process_params
        # Calculate the timestamp for 30 days ago
        @now   = Familia.now
        @since = (Familia.now - 30.days).to_i
      end

      def raise_concerns
        # API access entitlement required for metadata listing
        require_entitlement!('api_access')
      end

      def process
        # Debug logging for receipt list investigation
        OT.info '[DEBUG:ListReceipts] Starting query',
          {
            cust_id: cust&.custid,
            cust_objid: cust&.objid,
            receipts_dbkey: cust&.receipts&.dbkey,
            since: since,
            now: @now,
            now_int: @now.to_i,
            familia_now: Familia.now,
          }

        # Check what's in the sorted set before query
        total_in_set       = cust.receipts.size
        most_recent_scores = cust.receipts.revrangeraw(0, 2, with_scores: true)
        OT.info '[DEBUG:ListReceipts] Sorted set state',
          {
            total_in_set: total_in_set,
            most_recent_items: most_recent_scores,
          }

        # Fetch entries from the sorted set within the past 30 days
        # NOTE: Use @now (float) not @now.to_i - receipts are added with float scores
        # and truncating to int excludes receipts added in the same second
        @query_results     = cust.receipts.rangebyscore(since, @now)

        OT.info '[DEBUG:ListReceipts] Query results',
          {
            query_count: query_results.size,
            first_3_results: query_results.first(3),
          }

        # Get the safe fields for each record using optimized bulk loading
        receipt_objects = Onetime::Receipt.load_multi(query_results).compact
        @records        = receipt_objects.map(&:safe_dump)

        @has_items              = records.any?
        records.sort! { |a, b| b[:updated] <=> a[:updated] }
        @received, @notreceived = *records.partition { |m| m[:is_destroyed] }

        success_data
      end

      def success_data
        {
          'success' => true,
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
