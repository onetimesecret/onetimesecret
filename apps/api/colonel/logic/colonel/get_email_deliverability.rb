# apps/api/colonel/logic/colonel/get_email_deliverability.rb
#
# frozen_string_literal: true

require 'json'
require_relative '../base'
require 'onetime/models/email_suppression'

module ColonelAPI
  module Logic
    module Colonel
      # Get Email Deliverability Summary
      #
      # @api Returns the deliverability counters that diagnose a sender
      #   reputation problem: total suppressed addresses, bounces/complaints
      #   inside the recent window, and how many sends the suppression guard
      #   has skipped (the protection actually working). Requires colonel role.
      #
      # Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
      # Constant cost — two ZCARD-family counts, one GET, and one bounded
      # window read over the capped event feed.
      class GetEmailDeliverability < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelEmailDeliverability' }.freeze

        attr_reader :suppressed_total,
          :recent_bounces,
          :recent_complaints,
          :sends_skipped,
          :sync_status

        def process_params
          # No parameters — the window is fixed (EmailSuppression::RECENT_WINDOW).
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          recent             = Onetime::EmailSuppression.recent_event_counts
          @suppressed_total  = Onetime::EmailSuppression.count
          @recent_bounces    = recent[:bounce]
          @recent_complaints = recent[:complaint]
          @sends_skipped     = Onetime::EmailSuppression.sends_skipped.value
          @sync_status       = load_sync_status

          success_data
        end

        private

        # Per-provider last-sync markers. Familia's hgetall deserializes JSON
        # values, so each is already an object; a defensive JSON.parse guards
        # any legacy string value so the wire is ALWAYS objects, never strings.
        # Returns {} when nothing has ever synced (never null/absent).
        def load_sync_status
          raw = Onetime::EmailSuppression.sync_status.all || {}
          raw.transform_values do |value|
            if value.is_a?(String)
  begin
                                    JSON.parse(value)
  rescue StandardError
                                    value
  end
else
  value
end
          end
        end

        def success_data
          {
            record: {},
            details: {
              window_days: Onetime::EmailSuppression::RECENT_WINDOW / 86_400,
              counts: {
                suppressed_total: suppressed_total,
                recent_bounces: recent_bounces,
                recent_complaints: recent_complaints,
                sends_skipped: sends_skipped,
              },
              sync_status: sync_status,
            },
          }
        end
      end
    end
  end
end
