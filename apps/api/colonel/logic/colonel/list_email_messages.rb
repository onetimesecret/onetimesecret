# apps/api/colonel/logic/colonel/list_email_messages.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/recent_messages'

module ColonelAPI
  module Logic
    module Colonel
      # Recent outbound message log for the active transport (Track B, item 9).
      #
      # @api Returns a page of the provider's OWN sent-message log. Only
      #   Lettermint has a per-message API; SES (fire-and-forget) and every other
      #   transport return capability=false with an empty page. Requires colonel
      #   role.
      #
      # PII live-read rationale (mandatory): item 9 returns plaintext recipient
      # addresses + subjects sourced from the provider's message API. This is
      # EXEMPT from the epic's at-rest address-hashing posture BECAUSE it is a
      # live admin read, colonel-only, never persisted — do not flag it as a
      # hashing regression.
      #
      # Read-only: nothing mutates, so nothing is audited (CONTRACT 4). Fail-soft:
      # the op never raises — a provider timeout degrades the payload.
      class ListEmailMessages < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailMessages' }.freeze

        attr_reader :page, :per_page, :cursor, :result

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 30).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @per_page = 1 if @per_page < 1
          @page     = 1 if @page < 1
          # Opaque Lettermint page_cursor passthrough (nil unless a non-empty
          # cursor was supplied).
          @cursor   = params['cursor'] if params['cursor'] && !params['cursor'].to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::Email::RecentMessages.new(
            page: page, per_page: per_page, cursor: cursor,
          ).call
          success_data
        end

        def success_data
          {
            record: {},
            details: result.to_h,
          }
        end
      end
    end
  end
end
