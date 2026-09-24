# apps/api/colonel/logic/colonel/list_colonel_audit_events.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

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
      #   colonel role. Covers ALL THREE of the model's trails — operator
      #   activity, unauthenticated security telemetry and authenticated
      #   observations — merged chronologically and tagged with the `trail` each
      #   row came from; they are stored apart only so the chattier ones cannot
      #   evict the operator record.
      #
      # This is the read side of the flight recorder: every mutating admin op
      # writes an ColonelAuditEvent; this endpoint plays it back.
      #
      # ## Audited as an OBSERVATION (#4335)
      #
      # This mutates nothing, so under CONTRACT 4 it writes nothing to the
      # OPERATOR trail — and it still does not. It does record one observation
      # per request on the separate `access_events` trail, because "who has been
      # reading the audit log" is one of the first questions asked after an
      # incident and was the one question this log could not answer.
      #
      # The event is recorded AFTER the read completes, so the page an operator
      # receives is the trail as it stood before they looked — a listing never
      # contains the event describing itself. There is no recursion either way:
      # {Onetime::ColonelAuditReader} never writes, so the read cannot append to
      # what it is reading.
      class ListColonelAuditEvents < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelAuditEvents' }.freeze

        # The merge, the filters and the field allowlist now live in
        # {Onetime::ColonelAuditReader} — shared with the CSV/NDJSON export
        # endpoint and with `bin/ots audit list`, so the three readers cannot
        # drift on what an operator is allowed to see (#4334). This class keeps
        # only the pagination envelope, which is its own.
        Reader = Onetime::ColonelAuditReader

        # Ceiling on how many events a single read may load into Ruby: the
        # three trails' caps summed, i.e. the entire store. All are trimmed on
        # every write, so this is a fixed bound, not a function of traffic.
        # Aliased rather than moved: it is referenced by name in this class's
        # own logic.
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
            # Every trail the merge reads must be counted here, or pagination
            # under-reports and the last page silently truncates.
            @total_count = Onetime::ColonelAuditEvent.count +
                           Onetime::ColonelAuditEvent.security_count +
                           Onetime::ColonelAuditEvent.access_count
            @events      = merged_events(offset + per_page).slice(offset, per_page) || []
          end

          @total_pages = (total_count.to_f / per_page).ceil
          @events      = events.map { |event| format_event(event) }

          record_access_event

          success_data
        end

        private

        # One observation per request. Detail carries the SHAPE of the read —
        # which page, how wide, under which filters — never the rows returned:
        # an audit event about an audit read must not copy the trail into
        # itself. The filter values are already sanitized operator input.
        def record_access_event
          Onetime::ColonelAuditEvent.record_access(
            actor: cust&.extid,
            verb: Reader::AUDIT_VERB_LIST,
            target: Reader::AUDIT_TARGET,
            result: :success,
            detail: {
              page: page,
              per_page: per_page,
              returned: events.size,
              actor_filter: actor_filter,
              verb_filter: verb_filter,
            },
          )
        end

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
