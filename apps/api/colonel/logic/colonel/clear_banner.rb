# apps/api/colonel/logic/colonel/clear_banner.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/banner'

module ColonelAPI
  module Logic
    module Colonel
      # Clear the global broadcast banner (Colonel).
      #
      # Thin adapter over {Onetime::Operations::ClearBanner} — the single, audited
      # implementation of the clear verb (epic #41). This class keeps only the HTTP
      # concerns; the op owns the Redis delete, the runtime refresh, and the
      # AdminAuditEvent (CONTRACT 4).
      #
      # Idempotent by delegation: clearing when no banner is set is a no-op that
      # records NO audit event (the op returns :not_set). We return 200 with
      # `cleared: false` rather than a 404 so a benign race (the banner's TTL
      # expiring between the UI's read and the operator's confirm) is not surfaced
      # as an error — the destructive-action confirm is the UI's guardrail.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ClearBanner < ColonelAPI::Logic::Base
        attr_reader :result

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::ClearBanner.new(actor: cust.extid).call
          success_data
        end

        def success_data
          {
            record: {
              cleared: result.cleared,
              active: false,
            },
            details: {
              message: result.cleared ? 'Broadcast banner cleared' : 'No banner was set',
            },
          }
        end
      end
    end
  end
end
