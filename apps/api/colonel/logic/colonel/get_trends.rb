# apps/api/colonel/logic/colonel/get_trends.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Get Trends
      #
      # @api Returns per-day activity series for the admin overview dashboard:
      #   signups/day and secrets-created/day for the trailing 30 days (UTC,
      #   oldest first, today inclusive). Days with no data are zero-filled.
      #   Requires colonel role.
      #
      # Data is collected forward-only by Onetime::DailyMetric (incremented at
      # the Customer.create! and Receipt.spawn_pair chokepoints); there is no
      # backfill source, so days before the instrumentation shipped read 0 —
      # the UI presents the series as "collecting since first data point".
      # Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
      class GetTrends < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelTrends' }.freeze

        # Dashboard window. Fixed (not a param) so the endpoint stays a
        # constant-cost pair of MGETs.
        DAYS = 30

        attr_reader :signups, :secrets_created

        def process_params
          # No parameters — the window is fixed.
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @signups         = Onetime::DailyMetric.counts(:signups, DAYS)
          @secrets_created = Onetime::DailyMetric.counts(:secrets_created, DAYS)

          success_data
        end

        private

        def success_data
          {
            record: {},
            details: {
              days: DAYS,
              series: {
                signups: signups,
                secrets_created: secrets_created,
              },
            },
          }
        end
      end
    end
  end
end
