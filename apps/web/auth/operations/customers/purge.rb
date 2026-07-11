# apps/web/auth/operations/customers/purge.rb
#
# frozen_string_literal: true

# Reuses (does not rewrite) the incumbent delete primitive.
require 'auth/operations/delete_customer'

module Auth
  module Operations
    module Customers
      # ADMIN purge of a single customer: destroy the record and record it in the
      # admin audit trail.
      #
      # Reuses Auth::Operations::DeleteCustomer (the single delete primitive) and
      # layers on exactly one AdminAuditEvent per successful destroy (epic #20
      # CONTRACT 4 / #21). This is the colonel single-customer delete verb
      # (DELETE /api/colonel/users/:user_id).
      #
      # Scope note: this destroys the customer unconditionally — a colonel deleting
      # a specific account is an explicit, audited decision. The bulk
      # `bin/ots customers purge` inactivity sweep keeps its own billing-protection
      # heuristics and OT.info trail and deletes via the bare DeleteCustomer
      # primitive (it is a maintenance sweep, not per-record admin actions), so it
      # does not flood the capped audit set with thousands of events.
      class Purge
        # @!attribute status [r]
        #   @return [Symbol] :success (destroyed) or :not_found (nothing to delete)
        Result = Data.define(:status, :extid, :custid)

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous)
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        #   Never an internal objid.
        def initialize(customer:, actor:)
          @customer = customer
          @actor    = actor
        end

        # @return [Result]
        def call
          # Capture identity BEFORE destroy — the record is gone afterward.
          extid  = @customer.extid
          custid = @customer.custid

          deleted = Auth::Operations::DeleteCustomer.new(customer: @customer).call
          return Result.new(status: :not_found, extid: extid, custid: custid) unless deleted

          # One audit event per successful mutation. obscure_email is non-secret;
          # never put secret content / tokens / passphrases into detail.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: 'customer.purge',
            target: extid,
            result: :success,
            detail: { email: obscure(@customer) },
          )

          Result.new(status: :success, extid: extid, custid: custid)
        end

        private

        # obscure_email raises for anonymous; the caller guards non-anonymous, but
        # stay defensive so a purge never fails on audit-detail formatting.
        def obscure(customer)
          customer.obscure_email
        rescue StandardError
          nil
        end
      end
    end
  end
end
