# apps/api/colonel/logic/colonel/list_audit_events.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # List Audit Events
      #
      # @api Returns the admin audit trail (Onetime::AdminAuditEvent) newest
      #   first, with pagination and simple filters: `actor` (case-insensitive
      #   substring over the acting colonel's extid/email — the sessions-search
      #   idiom) and `verb` (an exact action like `customer.set_role`, or a
      #   category prefix like `customer` that matches `customer.*`). Requires
      #   colonel role.
      #
      # This is the read side of the flight recorder: every mutating admin op
      # writes an AdminAuditEvent; this endpoint plays it back. READ-ONLY —
      # per CONTRACT 4 (reads never audit), listing the log must never itself
      # write an audit event.
      class ListAuditEvents < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelAuditEvents' }.freeze

        attr_reader :events, :total_count, :page, :per_page, :total_pages,
          :actor_filter, :verb_filter

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
            # Filtered read: the events are opaque JSON members of one sorted
            # set, so filtering means loading and matching in Ruby. Bounded by
            # design — the set is hard-capped at MAX_EVENTS (10k) on every
            # write, so this can never become an unbounded enumeration.
            matching     = Onetime::AdminAuditEvent
              .recent(Onetime::AdminAuditEvent::MAX_EVENTS)
              .select { |event| matches_filters?(event) }
            @total_count = matching.size
            @events      = matching.slice(offset, per_page) || []
          else
            # Unfiltered read: a single ZREVRANGE slice of the requested page.
            @total_count = Onetime::AdminAuditEvent.count
            @events      = Onetime::AdminAuditEvent.recent(per_page, offset)
          end

          @total_pages = (total_count.to_f / per_page).ceil
          @events      = events.map { |event| format_event(event) }

          success_data
        end

        private

        def filters_active?
          !actor_filter.to_s.empty? || !verb_filter.to_s.empty?
        end

        def matches_filters?(event)
          unless actor_filter.to_s.empty?
            return false unless event['actor'].to_s.downcase.include?(actor_filter.downcase)
          end

          unless verb_filter.to_s.empty?
            verb = event['verb'].to_s
            return false unless verb == verb_filter || verb.start_with?("#{verb_filter}.")
          end

          true
        end

        # Emit the event fields explicitly (never the raw stored hash) so the
        # wire contract stays a deliberate allowlist even if the model grows
        # internal fields later.
        def format_event(event)
          {
            id: event['id'].to_s,
            actor: event['actor'].to_s,
            verb: event['verb'].to_s,
            target: event['target'].to_s,
            result: event['result'].to_s,
            detail: event['detail'],
            created: event['created'].to_f,
          }
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
