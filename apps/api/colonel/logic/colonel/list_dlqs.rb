# apps/api/colonel/logic/colonel/list_dlqs.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/dlq/list'

module ColonelAPI
  module Logic
    module Colonel
      # List every dead-letter queue with its depth (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Dlq::List} — the single
      # implementation of the DLQ list-all verb (epic #42). This class keeps only
      # the HTTP concerns (param coercion + role gate + in-memory pagination); the
      # op owns the bounded queue-summary read. Sits directly beside the existing
      # {GetQueueMetrics} read endpoint, upgrading the read-only queue widget into
      # an actionable DLQ console.
      #
      # Uses the shared boot-time `$rmq_conn` (like {GetQueueMetrics}) — no new
      # broker connection on the request path. When the broker is not connected the
      # list degrades to empty + `connected: false` rather than erroring.
      #
      # Read-only: no AdminAuditEvent (CONTRACT 4 — audit is for mutations).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListDlqs < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelDlqList' }.freeze

        DEFAULT_PER_PAGE = 50

        attr_reader :dlqs, :pagination_meta, :connected

        def process_params
          @page     = (params['page'] || 1).to_i
          @page     = 1 if @page < 1
          @per_page = (params['per_page'] || DEFAULT_PER_PAGE).to_i
          @per_page = DEFAULT_PER_PAGE if @per_page <= 0
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          rows = fetch_rows

          total_count = rows.size
          total_pages = @per_page.zero? ? 0 : (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page

          @dlqs            = rows[start_idx, @per_page] || []
          @pagination_meta = {
            page: @page,
            per_page: @per_page,
            total_count: total_count,
            total_pages: total_pages,
          }

          success_data
        end

        private

        # All DLQ summary rows (bounded — the fixed allowlist), or [] when the
        # broker is not connected.
        def fetch_rows
          unless $rmq_conn&.open?
            @connected = false
            return []
          end

          @connected = true
          Onetime::Operations::Dlq::List.new(connection: $rmq_conn).call.dlqs
        end

        def success_data
          {
            record: {},
            details: {
              dlqs: dlqs,
              pagination: pagination_meta,
              connected: connected,
            },
          }
        end
      end
    end
  end
end
