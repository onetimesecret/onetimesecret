# apps/web/auth/operations/customers/set_verification.rb
#
# frozen_string_literal: true

# Reuses (does not rewrite) the incumbent verification op. The CLI runs outside
# the auth app's autoloader, so require the dependency explicitly.
require 'auth/operations/set_customer_verification'

module Auth
  module Operations
    module Customers
      # ADMIN verification wrapper: set a customer's verified state as a colonel /
      # operator action, and record it in the admin audit trail.
      #
      # This deliberately does NOT re-implement verification — it delegates to the
      # incumbent Auth::Operations::SetCustomerVerification (the cross-store
      # Redis+SQL writer) and adds exactly one AdminAuditEvent on a successful
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
      #   raises SetCustomerVerification::{NoAuthDatabase, AccountNotFound}
      class SetVerification
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
        # @raise [SetCustomerVerification::NoAuthDatabase, SetCustomerVerification::AccountNotFound]
        def call
          result = Auth::Operations::SetCustomerVerification.new(
            customer: @customer,
            verified: @verified,
            verified_by: @verified_by,
            db: @db,
          ).call

          # Audit only an actual state change; a :no_change mutated nothing.
          if result == :success
            Onetime::AdminAuditEvent.record(
              actor: @actor,
              verb: 'customer.set_verification',
              target: @customer.extid,
              result: :success,
              detail: { verified: @verified },
            )
          end

          result
        end
      end
    end
  end
end
