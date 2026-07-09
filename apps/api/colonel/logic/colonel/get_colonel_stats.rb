# apps/api/colonel/logic/colonel/get_colonel_stats.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/sessions/store'

module ColonelAPI
  module Logic
    module Colonel
      # Get Colonel Stats
      #
      # @api Returns aggregate platform statistics including total customer,
      #   receipt, and secret counts. Requires colonel role.
      class GetColonelStats < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelStats' }.freeze

        attr_reader :session_count,
          :customer_count,
          :receipt_count,
          :secret_count,
          :secrets_created,
          :secrets_shared,
          :emails_sent

        def process_params
          # No parameters needed for stats endpoint
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          process_statistics

          success_data
        end

        def process_statistics
          @customer_count  = Onetime::Customer.count
          @receipt_count   = Onetime::Receipt.count
          @secret_count    = Onetime::Secret.count

          # Real count of session keys via the sessions store's bounded scan —
          # the same key definition GET /api/colonel/sessions lists. This was
          # hardcoded to 0 after session tracking moved to Rack::Session
          # middleware (QA 2026-07-07: dashboard reported 0 with live sessions).
          @session_count = Onetime::Operations::Sessions::Store.count(Familia.dbclient)

          # Global lifetime counters. These are real Familia class-level counters
          # (`Onetime::Customer.<name>`) maintained at the creation/send chokepoints:
          #   - secrets_created: incremented on secret create (v2 base_secret_action,
          #     incoming create_incoming_secret)
          #   - secrets_shared:  incremented on secret reveal (v2 reveal/show_secret)
          #   - emails_sent:     incremented on successful outbound delivery
          #     (Onetime::Mail::Delivery::Base#deliver)
          #
          # These were previously stubbed to 0 (issue #3653, debt §7). They are now
          # sourced from the true counters — no fabricated values.
          #
          # BACKFILL NOTE: these are forward-only counters. They tally events since
          # the chokepoint instrumentation was introduced and do NOT include
          # historical activity from before it. There is no reliable source to
          # backfill lifetime create/share/send totals (secrets expire; there is no
          # historical email log), so no backfill is performed here. This differs
          # from issue #60's per-customer *current* secret count, which is
          # recomputable from live `secret:*` keys and IS backfilled at rollout.
          @secrets_created = Onetime::Customer.secrets_created.to_i
          @secrets_shared  = Onetime::Customer.secrets_shared.to_i
          @emails_sent     = Onetime::Customer.emails_sent.to_i
        end
        private :process_statistics

        def success_data
          {
            record: {},
            details: {
              counts: {
                session_count: session_count,
                customer_count: customer_count,
                receipt_count: receipt_count,
                secret_count: secret_count,
                secrets_created: secrets_created,
                secrets_shared: secrets_shared,
                emails_sent: emails_sent,
              },
            },
          }
        end
      end
    end
  end
end
