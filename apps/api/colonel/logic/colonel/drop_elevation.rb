# apps/api/colonel/logic/colonel/drop_elevation.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # DELETE /api/colonel/elevation — end the step-up (sudo) window early
      # (#4327).
      #
      # Strictly de-escalating, and idempotent: dropping a window that is not
      # live is a no-op that still answers 200, because the operator's intent
      # ("I am done with elevated access") is satisfied either way and a 404 here
      # would only tell them whether they were elevated.
      #
      # Audited with .record — a deliberate, operator-initiated action on the
      # same trail as the matching ElevateSession success, so the pair reads as
      # one bracket. It shares that class's documented exception to CONTRACT 4:
      # there is no Operations class because the mutation is a session field.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class DropElevation < ColonelAPI::Logic::Base
        AUDIT_VERB = 'colonel.elevate_drop'

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @was_elevated = elevated?
          drop_elevation!
          record_audit

          success_data
        end

        def success_data
          {
            record: {
              elevated: false,
              expires_at: nil,
              seconds_remaining: 0,
            },
            details: {
              message: 'Elevation dropped',
              was_elevated: @was_elevated,
            },
          }
        end

        private

        def record_audit
          Onetime::ColonelAuditEvent.record(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: cust.extid,
            result: :success,
            detail: { was_elevated: @was_elevated },
          )
        rescue StandardError => ex
          OT.le('[DropElevation] audit record failed', exception: ex)
        end
      end
    end
  end
end
