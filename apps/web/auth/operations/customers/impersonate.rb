# apps/web/auth/operations/customers/impersonate.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/models/impersonation_grant'
require 'onetime/audited_failure'

module Auth
  module Operations
    module Customers
      # Issue a single-use, short-TTL impersonation grant for a customer.
      #
      # The ONE implementation of the impersonate verb. The CLI
      # `customers impersonate` command is a thin adapter over it; a future
      # colonel endpoint would be the second. This op does NOT establish a
      # session — see {Onetime::ImpersonationGrant} for why a session cannot be
      # safely minted from here (CLI/off-request), and why we mint a grant that
      # the WEB surface redeems instead.
      #
      # ## ADR-023 — no fabricated actor
      #
      # An impersonation MUST record the REAL operator as actor and the target as
      # subject, un-fakeably. This op refuses to run without a non-empty operator
      # actor ({MissingActor}) rather than mint an unattributable grant, and it
      # records the actor from inside #call (not from the CLI wrapper) so no
      # adapter can bypass it. Because the failure path is also audited
      # ({audit_failures}), a refused attempt is itself in the trail.
      #
      # ## Privilege guard
      #
      # A colonel-role account cannot be impersonated ({PrivilegedTarget}): a
      # session as a colonel would let a lower operator inherit colonel powers.
      # Mirrors SetSuspension's PrivilegedAccount refusal.
      class Impersonate
        include Onetime::LoggerMethods
        include Onetime::AuditedFailure

        AUDIT_VERB = 'customer.impersonate'

        # The privilege / precondition guards below raise BEFORE the success-path
        # record, so without this a refused impersonation attempt leaves no
        # trace. Records one result: :failure event and re-raises. Authorization
        # rejections are excluded by AuditedFailure by construction.
        audit_failures :call, verb: AUDIT_VERB, target: -> { @customer&.extid }

        # Raised when no real operator actor is supplied (ADR-023). Adapters
        # should also validate up front for good UX; this is the backstop.
        class MissingActor < StandardError; end

        # Raised when no justification is supplied. Impersonation without a
        # recorded reason is not permitted.
        class MissingReason < StandardError; end

        # Raised when asked to impersonate a colonel-role account.
        class PrivilegedTarget < StandardError; end

        # Raised when the target is the anonymous customer.
        class AnonymousTarget < StandardError; end

        # @!attribute status [r]
        #   @return [Symbol] :issued
        # @!attribute token [r]
        #   @return [String] the BEARER capability — the caller delivers it to the
        #     operator; it must never be logged.
        Result = Data.define(:status, :customer, :actor, :reason, :token, :grant_id, :expires_in)

        # @param customer [Onetime::Customer] target (caller ensures non-nil)
        # @param actor [String, #extid, #email] the REAL operator's PUBLIC
        #   identity. Normalized to a string here; empty/nil is refused.
        # @param reason [String] mandatory justification (recorded in the audit)
        # @param ttl [Integer, nil] grant lifetime in seconds; clamped by the
        #   grant model (nil resolves to the model default inside clamp_ttl).
        # @param grant_model [Class] injection seam for tests; defaults to
        #   Onetime::ImpersonationGrant.
        def initialize(customer:, actor:, reason:, ttl: nil, grant_model: Onetime::ImpersonationGrant)
          @customer    = customer
          @actor       = normalize_actor(actor)
          @reason      = reason.to_s.strip
          @ttl         = ttl
          @grant_model = grant_model
        end

        # @return [Result]
        # @raise [MissingActor, MissingReason, PrivilegedTarget, AnonymousTarget]
        def call
          # ADR-023: fail loud rather than mint an unattributable grant.
          raise MissingActor, 'Impersonation requires a real operator actor (ADR-023)' if @actor.to_s.strip.empty?
          raise MissingReason, 'Impersonation requires a reason' if @reason.empty?
          raise AnonymousTarget, 'Cannot impersonate an anonymous customer' if @customer.anonymous?

          if @customer.role.to_s == 'colonel'
            raise PrivilegedTarget, 'Cannot impersonate a colonel-role account.'
          end

          ttl   = @grant_model.clamp_ttl(@ttl)
          grant = @grant_model.issue(
            target_extid: @customer.extid,
            target_email: @customer.email,
            actor: @actor,
            reason: @reason,
            ttl: ttl,
          )

          # Audit records the NON-SECRET grant_id, never the bearer token (the
          # trail is colonel-readable; a token there is a redeemable capability).
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { reason: @reason, grant_id: grant.grant_id, ttl: ttl },
          )

          # debug (not info): the audit event is the durable record and the token
          # must stay out of logs (see SetRole for the CLI output-contract note).
          auth_logger.debug "[customer.impersonate] grant issued for #{@customer.extid} by #{@actor} ttl=#{ttl}"

          Result.new(
            status: :issued,
            customer: @customer,
            actor: @actor,
            reason: @reason,
            token: grant.token,
            grant_id: grant.grant_id,
            expires_in: ttl,
          )
        end

        private

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
