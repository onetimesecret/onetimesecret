# apps/api/colonel/logic/colonel/revoke_customer_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/sessions/revoke_for_customer'

module ColonelAPI
  module Logic
    module Colonel
      # Revoke one of a customer's sessions from the per-customer view (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Sessions::RevokeForCustomer} — the
      # mutating half of the per-customer session view (spec
      # docs/specs/colonel-ui/40-*). The op invalidates the session by deleting
      # the live encrypted `session:<sid>` blob (adaptation #1 — that, not a
      # Rodauth index row, is what logs the user out), tidies the sidecar + the
      # per-customer index, and writes ONE customer-scoped AdminAuditEvent.
      #
      # Deleting a session logs that user out mid-flight, so the UI gates this
      # behind typed-confirmation (same as the global DeleteSession).
      #
      # Idempotent: revoking an already-gone session still tidies + returns
      # `revoked: true` (unlike the global {DeleteSession}, which reports
      # `deleted: status == :deleted`).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RevokeCustomerSession < ColonelAPI::Logic::Base
        attr_reader :user_id, :session_id, :result

        def process_params
          @user_id    = sanitize_identifier(params['user_id'])
          @session_id = sanitize_identifier(params['session_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Session ID is required', field: :session_id) if session_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # actor is the acting colonel's PUBLIC id (extid), never an objid.
          @result = Onetime::Operations::Sessions::RevokeForCustomer.new(
            custid: user_id,
            session_id: session_id,
            actor: cust.extid,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              session_id: result.session_id,
              revoked: result.revoked,
            },
            details: {
              message: 'Session revoked successfully',
            },
          }
        end
      end
    end
  end
end
