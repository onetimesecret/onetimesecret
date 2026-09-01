# apps/api/colonel/logic/colonel/list_colonel_audit_events.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/colonel_audit_reader'

module ColonelAPI
  module Logic
    module Colonel
      # List Audit Events
      #
      # @api Returns the admin audit trail (Onetime::ColonelAuditEvent) newest
      #   first, with pagination and simple filters: `actor` (case-insensitive
      #   substring over the acting colonel's extid/email — the sessions-search
      #   idiom) and `verb` (an exact action like `customer.set_role`, or a
      #   category prefix like `customer` that matches `customer.*`). Requires
      #   colonel role. Covers BOTH of the model's trails — operator activity
      #   and unauthenticated security telemetry — merged chronologically; they
      #   are stored apart only so the latter cannot evict the former.
      #
      # This is the read side of the flight recorder: every mutating admin op
      # writes an ColonelAuditEvent; this endpoint plays it back. READ-ONLY —
      # per CONTRACT 4 (reads never audit), listing the log must never itself
      # write an audit event.
      class ListColonelAuditEvents < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelAuditEvents' }.freeze

        # The merge, the filters and the field allowlist now live in
        # {Onetime::ColonelAuditReader} — shared with the CSV/NDJSON export
        # endpoint and with `bin/ots audit list`, so the three readers cannot
        # drift on what an operator is allowed to see (#4334). This class keeps
        # only the pagination envelope, which is its own.
        Reader = Onetime::ColonelAuditReader

        # Ceiling on how many events a single read may load into Ruby: the two
        # trails' caps summed, i.e. the entire store. Both are trimmed on every
        # write, so this is a fixed bound, not a function of traffic. Aliased
        # rather than moved: it is referenced by name in this class's own logic.
        MAX_COMBINED = Reader::MAX_COMBINED

        attr_reader :events,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :actor_filter,
          :verb_filter

        def process_params
          @page         = (params['page'] || 1).to_i
          @per_page     = (params['per_page'] || 50).to_i
          @per_page     = 100 if @per_page > 100 # Max 100 per page
          @per_page     = 1 if @per_page < 1
          @page         = 1 if @page < 1
          @actor_filter = sanitize_plain_text(params['actor'], max_length: 255) if params['actor']
          @verb_filter  = sanitize_plain_text(params['verb'], max_length: 100) if params['verb']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          offset = (page - 1) * per_page

          if filters_active?
            # Filtered read: the events are opaque JSON members of the backing
            # sorted sets, so filtering means loading and matching in Ruby.
            # Bounded by design — both sets are hard-capped on every write, so
            # this can never become an unbounded enumeration.
            matching     = merged_events(MAX_COMBINED).select { |event| matches_filters?(event) }
            @total_count = matching.size
            @events      = matching.slice(offset, per_page) || []
          else
            @total_count = Onetime::ColonelAuditEvent.count + Onetime::ColonelAuditEvent.security_count
            @events      = merged_events(offset + per_page).slice(offset, per_page) || []
          end

          @total_pages = (total_count.to_f / per_page).ceil
          @events      = events.map { |event| format_event(event) }

          success_data
        end

        private

        # Newest-first view over BOTH audit trails.
        #
        # ColonelAuditEvent stores operator activity and unauthenticated security
        # telemetry in two separately-capped sorted sets, so that a flood of
        # anonymous events (e.g. reset-request throttle cap-hits) cannot evict
        # privileged records — see the WRITE-FREQUENCY INVARIANT on the model.
        # That split is a storage concern; the operator wants one chronological
        # feed, so the merge happens on read, in the shared reader.
        def merged_events(limit)
          Reader.merged(limit)
        end

        def filters_active?
          Reader.filters?(actor_filter, verb_filter)
        end

        def matches_filters?(event)
          Reader.matches?(event, actor: actor_filter, verb: verb_filter)
        end

        # Emit the event fields explicitly (never the raw stored hash) so the
        # wire contract stays a deliberate allowlist even if the model grows
        # internal fields later. Shared with the export endpoint and the CLI so
        # one allowlist governs every reader.
        def format_event(event)
          Reader.format_event(event)
        end

        def success_data
          {
            record: {},
            details: {
              events: events,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
                actor: actor_filter,
                verb: verb_filter,
              },
            },
          }
        end
      end
    end
  end
end
