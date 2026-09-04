# apps/api/colonel/logic/colonel/revoke_all_customer_sessions.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require_relative 'current_session'
require 'onetime/operations/sessions/revoke_all_for_customer'
require 'onetime/operations/sessions/revoke_all_for_customer_except_current'

module ColonelAPI
  module Logic
    module Colonel
      # Revoke ALL of a customer's sessions — the offboarding / takeover variant
      # of {RevokeCustomerSession} (spec docs/specs/colonel-ui/40-*).
      #
      # Thin adapter over {Onetime::Operations::Sessions::RevokeAllForCustomer}. The
      # op is two-tier: (a) a GUARANTEED, uncapped purge of every tracked
      # `session:<sid>` blob in Customer#active_sessions, plus (b) a BEST-EFFORT,
      # capped SCAN that sweeps genuinely untracked (pre-sidecar) blobs a
      # tracked-only revoke would miss. The tracked purge is the guarantee; the scan
      # is bounded by {Store::MAX_SCAN}, so when it truncates the op surfaces
      # `scan_capped` (Result + audit detail) rather than overstating totality. It
      # then tidies the sidecar + per-customer index, clears the Rodauth
      # active-session rows in full mode, and writes ONE ColonelAuditEvent
      # (verb `session.revoke_all`) with the kill counts.
      #
      # Bulk-destructive, so it is a POST+verb route (matching the local
      # `.../purge`, `.../replay` convention) and the UI gates it behind a danger
      # confirm dialog. The record's counts are surfaced to the operator so they
      # see how total the revoke actually was.
      #
      # ## Self-target is SUPPORTED, not refused (#4328)
      #
      # Every other self-target verb in this package answers 422. This one does
      # not, deliberately: the scenario the whole epic is written for is a leaked
      # colonel cookie, and "kill all my sessions" is the operator's first
      # containment step. Refusing it would remove their only in-console remedy
      # for the very compromise they are containing. So a self-target request is
      # routed to {Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent},
      # which spares the session they are working in — and the response says so.
      # If the current sid cannot be resolved at all (a Hash-backed session), we
      # refuse rather than revoke the operator's own session out from under them.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class RevokeAllCustomerSessions < ColonelAPI::Logic::Base
        include AccountIdentifier
        include CurrentSession

        SELF_TARGET_MESSAGE = 'Revoked all of your other sessions; this one was kept.'

        attr_reader :user_id, :user, :reason, :result

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier) — the latter
          # strips '@' and '.', which silently destroys an email identifier.
          # See AccountIdentifier.
          @user_id = sanitize_account_identifier(params['user_id'])
          # OPTIONAL operator-supplied why (#4338). See
          # ColonelAPI::Logic::Base#operator_reason_param.
          @reason  = operator_reason_param
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        # @return [Boolean] the target resolved to the acting colonel
        def self_target?
          @self_target
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first, then email, then objid. The 404
          # is new with #4328: revoke-all against an unknown identifier used to
          # return zero counts, which reads as "done" for a typo'd id. The
          # self-target routing and the confirmation token both need the record
          # anyway.
          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists?

          @self_target = user.objid == cust.objid

          # TIER 1 (#4326). The URL carries the extid; the confirmation is the
          # account's EMAIL (its extid only when it has none).
          guard_destructive_action!(
            tier: :destructive,
            confirm_with: account_confirm_token(user),
            confirm_subject: "the target account's email address (or its external id when it has none)",
            field: :user_id,
          )

          # INTERLOCK — step 4, after proof (#4328). The ONLY refusal on this
          # verb: a self-target whose current sid we cannot identify would fall
          # through to the all-inclusive op and sign the operator out. Fail safe.
          if self_target? && current_session_id.to_s.empty?
            raise_form_error(
              'Cannot revoke your own sessions: this request has no identifiable session to keep. ' \
              'Use sign-out, or revoke from a browser session.',
              field: :user_id,
            )
          end

          charge_destructive_budget!
        end

        def process
          @result = self_target? ? revoke_all_except_current : revoke_all

          success_data
        end

        def success_data
          {
            record: {
              revoked: result.revoked,
              blobs_deleted: result.blobs_deleted,
              untracked_deleted: result.untracked_deleted,
              # The except-current op is Redis-only by contract (it is also the
              # self-service password-change primitive), so it has no Rodauth
              # row count to report. Zero, not nil: the ack shape is fixed.
              rodauth_rows_deleted: self_target? ? 0 : result.rodauth_rows_deleted,
              scan_capped: result.scan_capped,
            },
            details: {
              message: self_target? ? SELF_TARGET_MESSAGE : 'All sessions revoked successfully',
            },
          }
        end

        private

        # The offboarding primitive: kills EVERY session and writes the
        # ColonelAuditEvent (CONTRACT 4 — the op owns the trail).
        #
        # `customer: user`, not `custid: user_id`: raise_concerns already
        # resolved (and the operator already confirmed) THIS record, so the op
        # must act on it rather than re-resolve the route param through the
        # extid index (drift, #4205/#4217, would silently zero-count the revoke).
        def revoke_all
          Onetime::Operations::Sessions::RevokeAllForCustomer.new(
            customer: user,
            actor: cust.extid, # acting colonel's PUBLIC id, never an objid
            reason: reason,    # optional operator-supplied why (#4338)
          ).call
        end

        # Containment for the acting colonel's own account: same guaranteed
        # tracked kill plus best-effort untracked sweep, but the session this
        # request arrived on is preserved. Redis-only (no Rodauth rows — see the
        # op's doc block). Naming an `actor` is what makes it write the one
        # ColonelAuditEvent this admin action owes the trail; the self-service
        # callers pass none and stay out of it.
        #
        # `customer: user`, not `custid: user_id` — same reason as #revoke_all:
        # act on the record raise_concerns resolved and the operator confirmed.
        def revoke_all_except_current
          Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.new(
            customer: user,
            except_session_id: current_session_id,
            actor: cust.extid, # acting colonel's PUBLIC id, never an objid
            reason: reason,    # optional operator-supplied why (#4338)
          ).call
        end
      end
    end
  end
end
