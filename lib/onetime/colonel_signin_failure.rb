# lib/onetime/colonel_signin_failure.rb
#
# frozen_string_literal: true

# Loaded directly by both emitters (a Rodauth hook and a core logic class)
# rather than left to ambient load order, matching the require convention at
# each of those sites.
require_relative 'models/colonel_audit_event'

module Onetime
  # ColonelSigninFailure — the one place a FAILED colonel sign-in becomes an
  # audit event (#4339).
  #
  # ## The gap this closes
  #
  # A successful `colonel.signin` has been audited since the trail gained a
  # signal for operator PRESENCE. A failed one recorded nothing at all, by an
  # explicit decision documented at both emitters. So the highest-signal
  # security event the trail could hold — somebody working through passwords
  # against an actual admin account — was the one event it did not hold. A
  # brute-force against a colonel was invisible; only the rate limiter's own
  # log lines marked it, and only once a cap was reached.
  #
  # ## Why the old rationale no longer applies
  #
  # Both emitters said the same thing, and it was true when written: the audit
  # set is capped by COUNT with no TTL, so an event an unauthenticated caller
  # can trigger is a log-eviction primitive — enough failed logins would flush
  # the real destructive-action trail. That argument is about `events`, and it
  # still holds for `events`. It stopped being an argument for recording
  # NOTHING when the store grew a second collection: failures land in
  # `security_events` via {Onetime::ColonelAuditEvent.record_security}, whose
  # 1k count cap and 7-day age bound are trimmed independently, so a flood here
  # can only ever evict other anonymous telemetry. That is the
  # WRITE-FREQUENCY INVARIANT working as designed, and it is also why this
  # writer needs NO throttle of its own: budget separation is the control, not
  # write frequency. (Volume is bounded in practice anyway — the login rate
  # limiter locks the subject out long before a flood of these accumulates.)
  #
  # ## Only accounts that actually exist, and only colonels
  #
  # The curated signal is "someone is targeting a real admin account". An event
  # per submitted address would be the opposite: an attacker could mint a row
  # for any string they liked, and the trail would fill with noise about
  # accounts that do not exist. So nothing is recorded unless the attempted
  # identity resolves to a Customer holding the colonel role.
  #
  # ## Never the raw address
  #
  # `target` is the OBSCURED email, exactly as the three rate-limiter security
  # events obscure their subjects: the audit trail must not become an
  # enumeration oracle, and every event also leaves the process at write time
  # on the `ColonelAudit` sink, so the payload has to be safe to ship. An
  # internal objid is equally out (see the actor-identity note on the model) —
  # and for a failed attempt an extid would be wrong on its own terms, since
  # nobody has proven they are that account.
  #
  # No client IP is recorded here. The three existing `record_security`
  # precedents record none either, and this event's job is DETECTION ("an admin
  # account is being worked on"), not attribution; the origin is in the auth
  # log line each site already writes, and in the limiter's own lockout lines.
  #
  # ## Why a module, and why a module FUNCTION
  #
  # Both emitters need the same lookup, the same role gate, the same obscured
  # target and the same fail-open rescue — non-trivial enough that duplicating
  # it would let the two auth modes drift, which is exactly what the shared
  # verb constant exists to prevent. It follows {Onetime::AuditReason}'s shape
  # (a small module under lib/onetime/ owning one cross-cutting audit concern)
  # but is called rather than included: full mode's site is the body of a
  # Rodauth hook, which is instance_exec'd on the Rodauth object, so a private
  # instance method mixed into the hook module would not be in scope there.
  #
  # ## Fail-open, and that includes the lookup
  #
  # {.record} never raises. A sign-in failure has to keep failing the same way,
  # at the same speed, whether or not this could resolve a Customer, reach
  # Valkey, or assemble an event — an audit helper on an unauthenticated code
  # path must not be a lever on the response. Callers therefore need no rescue
  # of their own.
  module ColonelSigninFailure
    # The coarse reason recorded on every event, matching the vocabulary the
    # sites' own failure logs already use (`reason: :invalid_credentials` in
    # simple mode).
    #
    # ONE value on purpose. Neither site can honestly say more: Rodauth's
    # after_login_failure does not distinguish "no such account" from "wrong
    # password" (see that hook's own comment), and where simple mode COULD
    # distinguish them, the unknown-account case records nothing at all. So by
    # the time an event is written, the account exists and the credential did
    # not match — which is precisely this.
    FAILURE_REASON = 'invalid_credentials'

    class << self
      # Record one `colonel.signin_failed` security event, if and only if the
      # attempted identity is a real colonel account.
      #
      # Callers supply whichever half of the identity they already hold, so the
      # guard never costs a redundant lookup on the failure path:
      #
      #   - `customer:` — simple mode resolved the address before comparing the
      #     passphrase, so it passes the result (INCLUDING nil for an unknown
      #     address, which is why omitting `login:` there is deliberate: a nil
      #     customer with no login means "already looked, not found", and this
      #     returns without touching the datastore).
      #   - `login:` — full mode holds only the submitted parameter, so this
      #     resolves it, normalizing the same way Rodauth's `normalize_login`
      #     does so the same address maps to the same account.
      #
      # @param auth_mode [String] 'simple' or 'full'. Passed as a literal by
      #   each site rather than read from config: a site knows its own mode
      #   structurally (simple mode never loads the auth app; the Rodauth hook
      #   exists only in full mode), and reading the config here could only
      #   ever disagree with reality.
      # @param customer [Onetime::Customer, nil] an already-resolved Customer.
      # @param login [String, nil] the submitted login, used only when
      #   `customer` is nil. Arbitrary attacker-controlled text; never stored.
      # @return [Hash, nil] the stored event, or nil when nothing was recorded
      #   (not a colonel, no such account, or the write failed).
      def record(auth_mode:, customer: nil, login: nil)
        customer = resolve(login) if customer.nil? && !login.nil?

        return nil if customer.nil?
        return nil unless customer.role.to_s == 'colonel'

        Onetime::ColonelAuditEvent.record_security(
          actor: 'anonymous',
          verb: Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN_FAILED,
          target: customer.obscure_email,
          result: :failure,
          detail: {
            auth_mode: auth_mode.to_s,
            failure_reason: FAILURE_REASON,
          },
        )
      rescue StandardError => ex
        # See the fail-open note in the module docs: this covers the lookup and
        # the assembly, and record_security already swallows its own errors.
        OT.le('[colonel.signin_failed] audit record failed', exception: ex)
        nil
      end

      private

      # Resolve a submitted login to a Customer, or nil.
      #
      # The Customer email index is an EXACT-match Familia index, so the
      # submitted value has to be normalized first or a legitimately-cased
      # address would miss. OT::Utils.normalize_email is the same helper
      # Rodauth's normalize_login uses (strip + NFC + case-fold), so every
      # variant Rodauth would resolve to one account resolves to one Customer
      # here too.
      def resolve(login)
        normalized = OT::Utils.normalize_email(login)
        return nil if normalized.empty?

        Onetime::Customer.find_by_email(normalized)
      end
    end
  end
end
