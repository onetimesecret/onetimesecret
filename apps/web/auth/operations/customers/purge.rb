# apps/web/auth/operations/customers/purge.rb
#
# frozen_string_literal: true

# Reuses (does not rewrite) the incumbent delete primitive.
require 'auth/operations/delete_customer'
require 'onetime/operations/sessions/revoke_all_for_customer'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'

module Auth
  module Operations
    module Customers
      # ADMIN purge of a single customer: revoke its sessions, destroy the record,
      # and record both mutations in the admin audit trail.
      #
      # Session revocation runs before Auth::Operations::DeleteCustomer (the single
      # delete primitive). Each mutation owns its audit event: session.revoke_all
      # for containment, then customer.purge after destruction. This is the colonel
      # single-customer delete verb (DELETE /api/colonel/users/:user_id).
      #
      # The revoke is handed the SAME resolved record this op holds, never its
      # extid: callers (PurgeUser logic, `customers purge-one`) may have resolved
      # by email or objid, and the extid index is not guaranteed to agree with
      # the record in hand (#4205, #4217 drift). A re-resolution miss would
      # degrade to a silent zero-count revoke followed by a destroy that leaves
      # live blobs/sidecars behind a deleted customer.
      #
      # Scope note: this destroys the customer unconditionally — a colonel deleting
      # a specific account is an explicit, audited decision. The bulk
      # `bin/ots customers purge` inactivity sweep keeps its own billing-protection
      # heuristics and OT.info trail and deletes via the bare DeleteCustomer
      # primitive (it is a maintenance sweep, not per-record admin actions), so it
      # does not flood the capped audit set with thousands of events.
      class Purge
        include Onetime::AuditedFailure
        include Onetime::AuditReason

        AUDIT_VERB = 'customer.purge'

        # The most destructive customer verb there is: a purge that raises
        # partway (DeleteCustomer blowing up mid-teardown) can leave the account
        # in an indeterminate state, and the success-path record below never
        # runs. Records one `result: :failure` and re-raises.
        audit_failures :call, verb: AUDIT_VERB, target: -> { @customer&.extid }

        # @!attribute status [r]
        #   @return [Symbol] :success (destroyed) or :not_found (nothing to delete)
        Result = Data.define(:status, :extid, :custid)

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous). Passed through as-is to the session revoke — see the
        #   class docs for why it is never re-resolved by extid.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        #   Never an internal objid.
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338),
        #   recorded in the audit detail. Blank is treated as absent and the
        #   detail keeps its pre-#4338 shape; see {Onetime::AuditReason},
        #   which also owns the 255-char bound and the optional-now /
        #   required-later rollout.
        def initialize(customer:, actor:, reason: nil)
          @customer = customer
          @actor    = actor
          @reason   = normalize_reason(reason)
        end

        # @return [Result]
        def call
          # Capture identity BEFORE destroy — the record is gone afterward.
          extid  = @customer.extid
          custid = @customer.custid

          # `customer:` not `custid: extid` — the op must act on the record we
          # hold, not on whatever the extid index resolves to (class docs).
          Onetime::Operations::Sessions::RevokeAllForCustomer.new(
            customer: @customer,
            actor: @actor,
            reason: @reason,
          ).call

          deleted = Auth::Operations::DeleteCustomer.new(customer: @customer).call
          return Result.new(status: :not_found, extid: extid, custid: custid) unless deleted

          # One audit event per successful mutation. obscure_email is non-secret;
          # never put secret content / tokens / passphrases into detail. The
          # operator's `reason` (#4338) rides in the same hash when supplied —
          # this is the verb where WHY matters most, since the account it
          # names no longer exists to be inspected.
          #
          # FAIL-CLOSED (#4333): the account is already gone by the time this
          # runs, so an unwritable event cannot be recovered from anywhere else.
          # Raising Onetime::AuditWriteFailure reports the purge as failed
          # rather than returning a clean :success for an action with no trail.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: extid,
            result: :success,
            detail: with_reason(email: obscure(@customer)),
            fail_closed: true,
          )

          Result.new(status: :success, extid: extid, custid: custid)
        end

        private

        # Customer#obscure_email does not raise on its own inputs: anonymous
        # returns a literal placeholder and OT::Utils.obscure_email yields nil for
        # a nil email. The rescue is kept as a belt-and-braces guard against
        # unexpected data (a malformed record mid-purge, a stub without the
        # method) — audit-detail formatting must never be why a purge fails.
        def obscure(customer)
          customer.obscure_email
        rescue StandardError
          nil
        end
      end
    end
  end
end
