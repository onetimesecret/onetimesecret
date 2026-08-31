# apps/api/colonel/logic/colonel/revoke_customer_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/models/session_metadata'
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
      # per-customer index, and writes ONE customer-scoped ColonelAuditEvent.
      #
      # Deleting a session logs that user out mid-flight, so the UI gates this
      # behind typed-confirmation (same as the global DeleteSession).
      #
      # ## Non-bearer identifier (finding F-01)
      #
      # The route no longer accepts a raw session id — that value is the live
      # `onetime.session` cookie and the `session:<sid>` blob key, so accepting
      # (or returning) it would let a colonel replay another user's cookie. The
      # per-customer list emits a non-reversible {Onetime::SessionMetadata#session_handle}
      # instead, and this endpoint accepts THAT. Because the handle is one-way, we
      # resolve the target sid by recomputing the handle over the OWNING customer's
      # own `active_sessions` set and matching — so the untrusted handle can only
      # ever name one of this customer's sessions, and the raw sid stays server-side.
      #
      # Idempotent within a live listing: revoking an already-gone session still
      # returns `revoked: true`. A handle that matches none of the customer's
      # current active sessions (stale/unknown) is a 404 — there is no session for
      # it to name — mirroring the global {DeleteSession} not-found.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RevokeCustomerSession < ColonelAPI::Logic::Base
        attr_reader :user_id, :session_handle, :session_id, :result

        def process_params
          @user_id        = sanitize_identifier(params['user_id'])
          @session_handle = sanitize_identifier(params['session_handle'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Session handle is required', field: :session_handle) if session_handle.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve the non-bearer handle back to the raw sid by matching it over
          # the target customer's own active-session set (the sids never leave the
          # server). 404 when it names none — a stale or unknown handle.
          @session_id = resolve_session_id
          raise_not_found('Session not found') if session_id.nil?
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
              # Echo the non-bearer handle the caller sent — NEVER the raw sid.
              session_handle: session_handle,
              revoked: result.revoked,
            },
            details: {
              message: 'Session revoked successfully',
            },
          }
        end

        private

        # Find the raw sid whose handle equals the submitted one, scanning only the
        # named customer's active_sessions (a small, bounded set). Returns nil when
        # the customer is unknown or no member matches. Customer resolution mirrors
        # RevokeForCustomer / ListForCustomer: extid → email → objid.
        def resolve_session_id
          customer = Onetime::Customer.load_by_extid_or_email(user_id) ||
                     Onetime::Customer.load(user_id)
          return nil unless customer&.exists?

          customer.active_sessions.revrange(0, -1).find do |sid|
            Onetime::SessionMetadata.handle_for(sid) == session_handle
          end
        end
      end
    end
  end
end
