# apps/web/auth/operations/customers/set_verification.rb
#
# frozen_string_literal: true

# Reuses (does not rewrite) the incumbent verification op. The CLI runs outside
# the auth app's autoloader, so require the dependency explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/operations/customers/role_support'
require 'auth/operations/set_customer_verification'

module Auth
  module Operations
    module Customers
      # ADMIN verification wrapper: set a customer's verified state as a colonel /
      # operator action, and record it in the admin audit trail.
      #
      # This deliberately does NOT re-implement verification — it delegates to the
      # incumbent Auth::Operations::SetCustomerVerification (the cross-store
      # Redis+SQL writer) and adds exactly one ColonelAuditEvent on a successful
      # change (epic #20 CONTRACT 4 / #21).
      #
      # ## Why a wrapper instead of auditing inside SetCustomerVerification
      #
      # SetCustomerVerification is also driven by the self-service Rodauth
      # `after_verify_account` hook — a customer verifying their own email is NOT
      # an admin action and must not land in the admin audit trail. Auditing there
      # would mislabel self-service verifications as admin activity. So the audit
      # lives in this admin-only wrapper; the colonel endpoint and the
      # `bin/ots customers verify/unverify` command call the wrapper, while the
      # Rodauth hook keeps calling the bare op.
      #
      # Return value and error classes are passed through unchanged so existing
      # adapters keep their exact control flow:
      #   :success | :no_change  (symbols, same as the underlying op)
      #   raises SetCustomerVerification::{NoAuthDatabase, AccountNotFound, AccountClosed}
      #
      # ## Interlocks (#4328 / review B-1)
      #
      # `has_system_role?` refuses every elevated role to an unverified account
      # ("Defense in depth: System roles require email verification"), so
      # UNVERIFYING a colonel is a demotion by another name — and it used to be
      # reachable in one un-gated POST, straight past any last-colonel check on
      # the role endpoint. Two refusals therefore live here, next to the audit,
      # so `bin/ots customers unverify` is bound by them too:
      #
      #   :self_unverify — the acting colonel unverifying their own account
      #   :last_colonel  — unverifying the only remaining active colonel
      #
      # They join the existing symbol contract rather than introducing a Result
      # struct, because three adapters already `case` on the returned symbol.
      class SetVerification
        include Onetime::AuditedFailure
        include Onetime::Operations::Customers::RoleSupport

        AUDIT_VERB = 'customer.set_verification'

        # Statuses that MUTATE nothing but each record one `result: :failure`
        # event. Same rationale as {Customers::SetRole::REFUSAL_STATUSES}: an
        # authenticated privileged refusal is traceable; an authorization
        # rejection is not audited at all.
        REFUSAL_STATUSES = [:last_colonel, :self_unverify].freeze

        # This wrapper's whole job is the audit event, and the three documented
        # error classes below are ALL raised by the inner op BEFORE it — so an
        # operator repeatedly trying to verify a closed or missing account left
        # no trace at all, which is precisely the state the trail exists to show.
        # NoAuthDatabase additionally means the cross-store write could not even
        # be attempted. Records one `result: :failure` and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @customer&.extid },
          detail: -> { { verified: @verified } }

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous)
        # @param verified [Boolean] target state
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param verified_by [String, nil] provenance tag passed through to the
        #   underlying op ('cli_provision', 'colonel_admin', …); nil when clearing
        # @param actor_objid [String, nil] the acting colonel's INTERNAL id, for
        #   the self-unverify comparison only (the AUDIT actor stays the public
        #   id above). nil for the CLI and for the self-service callers, which
        #   have no acting colonel.
        # @param enforce_interlocks [Boolean] apply the #4328 unverify refusals.
        #   TRUE for every ADMINISTRATIVE unverify (the colonel endpoint, the
        #   CLI). FALSE only for a CREDENTIAL-PROVENANCE reset — clearing
        #   verification because the address itself changed and is now unproven
        #   (Customers::ChangeEmail). Refusing that would be strictly worse than
        #   the lockout it prevents: it would leave a colonel verified against
        #   an address nobody has proven they control.
        # @param db [Sequel::Database, nil] injectable, passed through
        def initialize(customer:, verified:, actor:, verified_by:, actor_objid: nil,
                       enforce_interlocks: true, db: nil)
          @customer           = customer
          @verified           = verified
          @actor              = actor
          @verified_by        = verified_by
          @actor_objid        = actor_objid
          @enforce_interlocks = enforce_interlocks
          @db                 = db
        end

        # @return [Symbol] :success or :no_change (passthrough from the inner
        #   op), or :self_unverify / :last_colonel when an interlock refused
        # @raise [SetCustomerVerification::NoAuthDatabase, SetCustomerVerification::AccountNotFound,
        #   SetCustomerVerification::AccountClosed]
        def call
          # INTERLOCKS (#4328) run BEFORE the cross-store write, so a refusal
          # mutates nothing. Only the UNVERIFY arm is interlocked; verifying is
          # the restorative direction and can never cause a lockout.
          refusal = unverify_refusal
          return build(refusal) if refusal

          result = Auth::Operations::SetCustomerVerification.new(
            customer: @customer,
            verified: @verified,
            verified_by: @verified_by,
            db: @db,
          ).call

          # POST-WRITE re-validation (#4328), mirroring SetRole. unverify_refusal
          # above is a check-then-act and is NOT atomic: two concurrent unverifies
          # of the two distinct last colonels can each pass the pre-check and both
          # write, leaving the install with zero verified colonels — recoverable
          # only from the CLI. Re-run the roster check AFTER the write; if this
          # unverify emptied it, roll the unverify back (re-verify) and refuse
          # through the SAME build exit, so the :last_colonel failure still audits.
          # Over-preserving on a concurrent double-rollback is the safe direction.
          if result == :success && unverify_left_no_colonel?
            Auth::Operations::SetCustomerVerification.new(
              customer: @customer,
              verified: true,
              verified_by: @verified_by,
              db: @db,
            ).call
            return build(:last_colonel)
          end

          # Audit only an actual state change; a :no_change mutated nothing.
          if result == :success
            Onetime::ColonelAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: @customer.extid,
              result: :success,
              detail: { verified: @verified },
            )
          end

          build(result)
        end

        private

        # @return [Symbol, nil] the refusal status, or nil to proceed
        def unverify_refusal
          return nil if @verified
          return nil unless @enforce_interlocks

          return :self_unverify if !@actor_objid.to_s.empty? && @actor_objid == @customer.objid
          return :last_colonel if last_colonel_by_verification?(@customer)

          nil
        end

        # Did the just-applied UNVERIFY remove the last verified colonel? (#4328
        # post-write re-validation.) Only meaningful for an interlocked unverify
        # of a colonel — the verify arm and provenance resets can never cause a
        # lockout, and unverifying a non-colonel cannot empty the roster, so all
        # three are guarded before the roster read (mirrors the pre-check).
        def unverify_left_no_colonel?
          return false if @verified
          return false unless @enforce_interlocks
          return false unless @customer.role.to_s == 'colonel'

          active_colonels.empty?
        end

        # Single exit point, so the refusal audit cannot be forgotten at an
        # early return (Memberships::Remove#build).
        def build(status)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          status
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        def record_refusal(status)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :failure,
            detail: { reason: status.to_s, verified: @verified },
          )
        rescue StandardError => ex
          OT.le "[Customers::SetVerification] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end
