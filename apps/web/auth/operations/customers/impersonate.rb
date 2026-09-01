# apps/web/auth/operations/customers/impersonate.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/entitlement_preview'
require 'onetime/session/impersonation'

module Auth
  module Operations
    module Customers
      # START a colonel impersonation on the CURRENT session.
      #
      # The ONE implementation of the impersonate verb; the colonel endpoint
      # (ColonelAPI::Logic::Colonel::ImpersonateUser) is a thin adapter over
      # it. Writes the session marker, records the audit event, and returns the
      # non-secret correlation id.
      #
      # ## Why this takes a session instead of minting a capability
      #
      # An earlier iteration issued a bearer grant that the web surface would
      # redeem, so a CLI could start an impersonation. But the only redeemer
      # that yields a VERIFIED actor is an authenticated colonel on the web
      # surface, and there issuance and redemption happen inside one request —
      # so the grant crossed no boundary and carried nothing. What it did add
      # was a redeemable capability with a TTL, sitting in a datastore. The
      # session marker is strictly less material: it exists only inside the
      # operator's own already-authenticated session.
      #
      # ## ADR-023 — no fabricated actor
      #
      # An impersonation MUST record the REAL operator as actor and the target
      # as subject, un-fakeably. This op refuses to run without a non-empty
      # operator actor ({MissingActor}) rather than start an unattributable
      # impersonation, and it records the actor from inside #call (not from the
      # adapter) so no caller can bypass it. The failure path is audited too
      # ({audit_failures}), so a refused attempt is itself in the trail.
      #
      # ## Guards
      #
      # A colonel-role target ({PrivilegedTarget}) would let a lower operator
      # inherit colonel powers — mirrors SetSuspension's PrivilegedAccount
      # refusal. A suspended target ({SuspendedTarget}) is rejected because
      # BaseSessionAuthStrategy refuses suspended customers on every request,
      # so the resulting overlay would be immediately invalid anyway. And an
      # already-impersonating session ({AlreadyImpersonating}) must be stopped
      # first: silently replacing the marker would leave the first
      # impersonation with no stop event.
      class Impersonate
        include Onetime::LoggerMethods
        include Onetime::AuditedFailure

        AUDIT_VERB = Onetime::SessionImpersonation::AUDIT_VERB_START

        # The privilege / precondition guards below raise BEFORE the
        # success-path record, so without this a refused impersonation attempt
        # leaves no trace. Records one result: :failure event and re-raises.
        # Authorization rejections are excluded by AuditedFailure by
        # construction.
        audit_failures :call, verb: AUDIT_VERB, target: -> { @customer&.extid }

        # Raised when no real operator actor is supplied (ADR-023). Adapters
        # should also validate up front for good UX; this is the backstop.
        class MissingActor < StandardError; end

        # Raised when no justification is supplied. Impersonation without a
        # recorded reason is not permitted.
        class MissingReason < StandardError; end

        # Raised when there is no session to place the marker on. Guards
        # against an adapter (or a future CLI) trying to start an
        # impersonation off-request, which cannot work by construction.
        class MissingSession < StandardError; end

        # Raised when asked to impersonate a colonel-role account.
        class PrivilegedTarget < StandardError; end

        # Raised when the target is the anonymous customer.
        class AnonymousTarget < StandardError; end

        # Raised when the target is suspended.
        class SuspendedTarget < StandardError; end

        # Raised when this session is already impersonating someone.
        class AlreadyImpersonating < StandardError; end

        # @!attribute status [r]
        #   @return [Symbol] :started
        # @!attribute impersonation_id [r]
        #   @return [String] NON-SECRET correlation id ("imp_…"), safe to log,
        #     audit, and return to the client. There is no bearer token.
        Result = Data.define(:status, :customer, :actor, :reason, :impersonation_id, :expires_at)

        # @param customer [Onetime::Customer] target (caller ensures non-nil)
        # @param actor [String, #extid, #email] the REAL operator's PUBLIC
        #   identity. Normalized to a string here; empty/nil is refused.
        # @param reason [String] mandatory justification (recorded in the audit)
        # @param session [#[]=] the operator's live Rack session — the thing
        #   the marker is written to.
        def initialize(customer:, actor:, reason:, session:)
          @customer = customer
          @actor    = normalize_actor(actor)
          @reason   = reason.to_s.strip
          @session  = session
        end

        # @return [Result]
        # @raise [MissingActor, MissingReason, MissingSession, PrivilegedTarget,
        #   AnonymousTarget, SuspendedTarget, AlreadyImpersonating]
        def call
          validate!

          # An entitlement preview would silently distort what the operator
          # sees "as the customer" — the whole point of impersonating is to see
          # the customer's real limits and affordances. End it here rather than
          # letting two overlays stack.
          Onetime::EntitlementPreview.clear_session!(@session)

          marker = Onetime::SessionImpersonation.start!(
            @session,
            target: @customer,
            reason: @reason,
          )

          record_start(marker)

          Result.new(
            status: :started,
            customer: @customer,
            actor: @actor,
            reason: @reason,
            impersonation_id: marker['id'],
            expires_at: marker['expires_at'],
          )
        end

        private

        def validate!
          # ADR-023: fail loud rather than start an unattributable session.
          raise MissingActor, 'Impersonation requires a real operator actor (ADR-023)' if @actor.to_s.strip.empty?
          raise MissingReason, 'Impersonation requires a reason' if @reason.empty?
          raise MissingSession, 'Impersonation requires a live session' unless @session.respond_to?(:[]=)
          raise AnonymousTarget, 'Cannot impersonate an anonymous customer' if @customer.anonymous?
          raise PrivilegedTarget, 'Cannot impersonate a colonel-role account.' if @customer.role.to_s == 'colonel'
          raise SuspendedTarget, 'Cannot impersonate a suspended account.' if @customer.suspended?

          return unless Onetime::SessionImpersonation.active(@session)

          raise AlreadyImpersonating, 'This session is already impersonating a customer.'
        end

        def record_start(marker)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: {
              reason: @reason,
              impersonation_id: marker['id'],
              expires_at: marker['expires_at'],
            },
          )

          auth_logger.info(
            "[customer.impersonate.start] #{@customer.extid} by #{@actor} id=#{marker['id']}",
          )
        end

        # Normalize actor to a PUBLIC identity string (extid/email), never an
        # internal objid. Returns nil for an unusable actor so #call can refuse.
        def normalize_actor(actor)
          return actor if actor.is_a?(String)
          return actor.extid if actor.respond_to?(:extid) && !actor.extid.to_s.empty?
          return actor.email if actor.respond_to?(:email)

          nil
        end
      end
    end
  end
end
