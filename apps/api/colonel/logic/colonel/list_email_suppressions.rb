# apps/api/colonel/logic/colonel/list_email_suppressions.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/models/email_suppression'

module ColonelAPI
  module Logic
    module Colonel
      # List Email Suppressions
      #
      # @api Returns the outbound suppression list (Onetime::EmailSuppression)
      #   newest first, with pagination and an EXACT-address `search` (the
      #   store is keyed by address, so search is a single O(1) lookup —
      #   deliberately not a substring scan). Requires colonel role.
      #
      # Read-only: reads never audit (CONTRACT 4).
      class ListEmailSuppressions < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailSuppressions' }.freeze

        attr_reader :suppressions, :total_count, :page, :per_page, :total_pages, :search

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @per_page = 1 if @per_page < 1
          @page     = 1 if @page < 1
          @search   = sanitize_plain_text(params['search'], max_length: 255) if params['search']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          if search.to_s.empty?
            # Unfiltered read: one ZREVRANGE page over the created-at index.
            offset        = (page - 1) * per_page
            @total_count  = Onetime::EmailSuppression.count
            @suppressions = Onetime::EmailSuppression.list(limit: per_page, offset: offset)
          else
            # Exact-address search: a single keyed lookup, 0 or 1 rows.
            entry         = Onetime::EmailSuppression.lookup(search)
            @suppressions = entry ? [entry] : []
            @total_count  = suppressions.size
          end

          @total_pages  = (total_count.to_f / per_page).ceil
          @suppressions = suppressions.map { |entry| format_entry(entry) }

          success_data
        end

        private

        # Emit fields explicitly (never the raw stored hash) so the wire
        # contract stays a deliberate allowlist — the ListAuditEvents idiom.
        def format_entry(entry)
          {
            address: entry['address'].to_s,
            reason: entry['reason'].to_s,
            source: entry['source'].to_s,
            created: entry['created'].to_f,
          }
        end

        def success_data
          {
            record: {},
            details: {
              suppressions: suppressions,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
                search: search,
              },
            },
          }
        end
      end
    end
  end
end
