# apps/api/colonel/logic/colonel/list_email_deliverability_events.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/models/email_suppression'

module ColonelAPI
  module Logic
    module Colonel
      # List Email Deliverability Events
      #
      # @api Returns the bounce/complaint event feed (Onetime::EmailSuppression
      #   events) newest first, with pagination. This is the raw feedback
      #   stream behind the deliverability summary — what bounced, when, and
      #   which source reported it. Requires colonel role.
      #
      # Read-only: reads never audit (CONTRACT 4). Bounded by design — the
      # feed is hard-capped at MAX_EVENTS on every write.
      class ListEmailDeliverabilityEvents < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailDeliverabilityEvents' }.freeze

        attr_reader :events, :total_count, :page, :per_page, :total_pages

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @per_page = 1 if @per_page < 1
          @page     = 1 if @page < 1
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          offset       = (page - 1) * per_page
          @total_count = Onetime::EmailSuppression.event_count
          @events      = Onetime::EmailSuppression.recent_events(per_page, offset)
          @total_pages = (total_count.to_f / per_page).ceil
          @events      = events.map { |event| format_event(event) }

          success_data
        end

        private

        # Emit fields explicitly (never the raw stored hash) — the
        # ListAuditEvents allowlist idiom.
        def format_event(event)
          {
            id: event['id'].to_s,
            address: event['address'].to_s,
            kind: event['kind'].to_s,
            reason: event['reason'].nil? ? nil : event['reason'].to_s,
            source: event['source'].to_s,
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
              },
            },
          }
        end
      end
    end
  end
end
