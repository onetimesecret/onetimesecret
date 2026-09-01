# apps/web/auth/operations/customers/set_verification.rb
#
# frozen_string_literal: true

# Reuses (does not rewrite) the incumbent verification op. The CLI runs outside
# the auth app's autoloader, so require the dependency explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
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
      # change (epic #20 CONTRACT 4 / #21) — and, since #4337, one per
      # no-change attempt too, under the same verb with
      # `outcome: 'no_change'`.
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
      class SetVerification
        include Onetime::AuditedFailure

        AUDIT_VERB = 'customer.set_verification'

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
        # @param db [Sequel::Database, nil] injectable, passed through
        def initialize(customer:, verified:, actor:, verified_by:, db: nil)
          @customer    = customer
          @verified    = verified
          @actor       = actor
          @verified_by = verified_by
          @db          = db
        end

        # @return [Symbol] :success or :no_change (passthrough from the inner op)
        # @raise [SetCustomerVerification::NoAuthDatabase, SetCustomerVerification::AccountNotFound,
        #   SetCustomerVerification::AccountClosed]
        def call
          result = Auth::Operations::SetCustomerVerification.new(
            customer: @customer,
            verified: @verified,
            verified_by: @verified_by,
            db: @db,
          ).call

          record_audit_event(result)

          result
        end

        private

        # ONE event per call, on the OPERATOR trail, whatever the inner op did.
        #
        # A `:no_change` mutated nothing, but it is still a deliberate admin
        # attempt to verify (or unverify) a named account, so it is recorded
        # under the same verb with `outcome: 'no_change'` (#4337) rather than
        # dropped — the same reasoning as SetRole and SetSuspension. Without it
        # the trail could show nothing while an operator repeatedly poked at an
        # account's verification state.
        #
        # NOT fail-closed on either path: verification is reversible and
        # destroys nothing.
        def record_audit_event(result)
          detail = { verified: @verified }
          detail = { outcome: 'no_change' }.merge(detail) unless result == :success

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: detail,
          )
        end
      end
    end
  end
end
