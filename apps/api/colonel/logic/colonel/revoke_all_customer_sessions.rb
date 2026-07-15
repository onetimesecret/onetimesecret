# apps/api/colonel/logic/colonel/revoke_all_customer_sessions.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/sessions/revoke_all_for_customer'

module ColonelAPI
  module Logic
    module Colonel
      # Revoke ALL of a customer's sessions — the offboarding / takeover variant
      # of {RevokeCustomerSession} (spec docs/specs/colonel-ui/40-*).
      #
      # Thin adapter over {Onetime::Operations::Sessions::RevokeAllForCustomer}. The
      # op guarantees a total lockout: a bounded SCAN deletes every live
      # `session:<sid>` blob for the customer — including pre-sidecar sessions a
      # tracked-only revoke would miss (adaptation: completeness > cost for this
      # rare, deliberate action) — tidies the sidecar + per-customer index, clears
      # the Rodauth active-session rows in full mode, and writes ONE
      # AdminAuditEvent (verb `session.revoke_all`) with the kill counts.
      #
      # Bulk-destructive, so it is a POST+verb route (matching the local
      # `.../purge`, `.../replay` convention) and the UI gates it behind a danger
      # confirm dialog. The record's counts are surfaced to the operator so they
      # see how total the revoke actually was.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RevokeAllCustomerSessions < ColonelAPI::Logic::Base
        attr_reader :user_id, :result

        def process_params
          @user_id = sanitize_identifier(params['user_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # actor is the acting colonel's PUBLIC id (extid), never an objid.
          @result = Onetime::Operations::Sessions::RevokeAllForCustomer.new(
            custid: user_id,
            actor: cust.extid,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              revoked: result.revoked,
              blobs_deleted: result.blobs_deleted,
              untracked_deleted: result.untracked_deleted,
              rodauth_rows_deleted: result.rodauth_rows_deleted,
              scan_capped: result.scan_capped,
            },
            details: {
              message: 'All sessions revoked successfully',
            },
          }
        end
      end
    end
  end
end
