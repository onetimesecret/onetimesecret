# lib/onetime/security/saml_assertion_replay_guard.rb
#
# frozen_string_literal: true

require 'digest'

module Onetime
  module Security
    # SamlAssertionReplayGuard - one-shot claim on a SAML assertion ID (#4450)
    #
    # A SAML Response delivered over the HTTP-POST binding is a bearer
    # document: it travels through the user's browser, and anything that can
    # read it there (a proxy log, a browser extension, an XSS on the IdP's
    # side of the form post) can re-POST it to the ACS URL. ruby-saml checks
    # signature, audience, recipient and the NotBefore/NotOnOrAfter window —
    # none of which stop a second presentation inside the window. SAML Core
    # (profiles §4.1.4.5) therefore REQUIRES the SP to "ensure that bearer
    # assertions are not replayed, by maintaining the set of used ID values
    # for the length of time for which the assertion would be considered
    # valid". This module is that set.
    #
    # The request binding in OmniAuth::Strategies::RequestBoundSAML (the SIGNED
    # assertion's SubjectConfirmationData/@InResponseTo must equal the pending
    # AuthnRequest id, which is consumed on first use) already makes a replay
    # useless to anyone who does not also hold a victim session whose pending
    # id the IdP wrote into that very assertion — which no later session can
    # have. The replay cache is the independent second control the spec asks
    # for: it does not depend on session state, so it still holds if the
    # session-side binding is ever weakened by a gem bump.
    #
    # One atomic gate, same shape as VerificationResendCooldown:
    #
    #   SET saml:assertion:{sha256} '1' NX EX <ttl>
    #
    # The first presentation claims the key; every later one sees NX fail.
    #
    # KEY: SHA-256 over (idp_entity_id, assertion_id), length-prefixed so no
    # pair of inputs can collide by moving bytes across the boundary. The
    # digest exists because both inputs are IdP-controlled strings of
    # arbitrary length and content — hashing bounds the key size and keeps
    # IdP-chosen bytes out of the keyspace. Scoping by IdP means two IdPs that
    # happen to mint the same assertion ID (tenants behind one install) cannot
    # deny each other's logins. The caller passes the CONFIGURED entity id,
    # which the strategy has already proven equal to the response Issuer.
    #
    # LIFETIME BOUND: ruby-saml's validate_conditions has no maximum — it
    # accepts any NotOnOrAfter in the future — and NotOnOrAfter is
    # IdP-controlled. A key that must outlive a day-long (or year-9999)
    # assertion would park in the datastore indefinitely, and a key that is
    # capped SHORTER than the assertion leaves the assertion replayable once
    # the key expires. Neither is acceptable, so the guard does not clamp
    # silently: `lifetime_exceeded?` tells the caller that an assertion is
    # valid for longer than MAX_LIFETIME past now (plus the clock drift the
    # response was validated with, so an IdP clock running ahead by the
    # tolerated amount does not cause refusals), and the caller REFUSES such
    # an assertion before claiming anything. Mainstream IdPs issue 5-60 minute
    # windows (Okta 5 min, Entra ID and AD FS 60 min), so one hour admits all
    # of them and refuses only the pathological.
    #
    # TTL: (NotOnOrAfter - now) + clock drift, because ruby-saml accepts the
    # assertion until NotOnOrAfter + allowed_clock_drift — the key must outlive
    # the last instant the gem would still validate the document. Floored at
    # MIN_TTL (EX 0 is a Redis error, and a just-expiring assertion that the
    # gem accepted inside its drift allowance must still be recorded). The
    # upper clamp (`max_ttl_for`) is MAX_LIFETIME + 2 x drift: for every
    # assertion `lifetime_exceeded?` admits it never binds, so the key is
    # guaranteed to outlive the gem's acceptance window. It exists only so a
    # caller that skipped `lifetime_exceeded?` still cannot park a key
    # indefinitely.
    #
    # FAIL SEMANTICS: datastore errors propagate (they are never rescued
    # here), matching the other lib/onetime/security/ primitives. The caller
    # MUST treat a raise as a refusal — a datastore outage must never turn
    # into an unguarded login path. Blank inputs raise ArgumentError for the
    # same reason: a caller that lost the assertion id must not end up
    # claiming (and thereafter colliding on) the digest of the empty string.
    #
    # Redis key (string keys at the Redis boundary):
    #   - saml:assertion:{sha256 hex}  - claim flag, EX-expired
    #
    # Usage:
    #   claimed = Onetime::Security::SamlAssertionReplayGuard.claim(
    #     idp_entity_id: 'https://idp.example.com/metadata',
    #     assertion_id: response.assertion_id,
    #     not_on_or_after: response.not_on_or_after,
    #     clock_drift: 60,
    #   )
    #   refuse! unless claimed
    module SamlAssertionReplayGuard
      KEY_PREFIX = 'saml:assertion'

      # Seconds. EX must be a positive integer.
      MIN_TTL = 1

      # Seconds. The longest (NotOnOrAfter - now) the caller should accept,
      # before clock drift. See LIFETIME BOUND above.
      MAX_LIFETIME = 3600

      extend self

      # Atomically claim an assertion. Returns true exactly once per
      # (idp_entity_id, assertion_id) within the TTL; false means the
      # assertion was already presented and the caller must refuse it.
      #
      # @param idp_entity_id [String] the CONFIGURED IdP EntityID
      # @param assertion_id [String] Assertion/@ID from the validated response
      # @param not_on_or_after [Time] Conditions/@NotOnOrAfter
      # @param clock_drift [Numeric] the allowed_clock_drift the response was
      #   validated with (seconds)
      # @param now [Time] injectable clock for tests
      # @param dbclient [Redis, nil] injectable client for tests
      # @return [Boolean] true when claimed, false when replayed
      # @raise [ArgumentError] blank identifier or non-Time expiry
      # @raise [Redis::BaseError] datastore failure — caller fails closed
      def claim(idp_entity_id:, assertion_id:, not_on_or_after:, clock_drift: 0, now: Time.now, dbclient: nil)
        key = key_for(idp_entity_id, assertion_id)
        ttl = ttl_for(not_on_or_after, clock_drift: clock_drift, now: now)
        db  = dbclient || Familia.dbclient

        # redis-rb returns true when the key was set, false when NX refused.
        # Compare strictly: anything that is not an explicit `true` (nil, a
        # pipelined Future, a surprising reply) is NOT a claim.
        db.set(key, '1', nx: true, ex: ttl) == true
      end

      # @return [String] datastore key for this (IdP, assertion) pair
      # @raise [ArgumentError] when either identifier is blank
      def key_for(idp_entity_id, assertion_id)
        idp = idp_entity_id.to_s
        aid = assertion_id.to_s
        raise ArgumentError, 'idp_entity_id is blank' if idp.strip.empty?
        raise ArgumentError, 'assertion_id is blank' if aid.strip.empty?

        # Length-prefixed so ("ab", "c") and ("a", "bc") hash differently.
        digest = Digest::SHA256.hexdigest("#{idp.bytesize}:#{idp}|#{aid.bytesize}:#{aid}")
        "#{KEY_PREFIX}:#{digest}"
      end

      # Whether the assertion stays valid for longer than the guard is willing
      # to remember it. The caller MUST refuse when this is true; `claim` does
      # not check it (so the refusal carries its own reason, not the guard's
      # error class).
      #
      # @param not_on_or_after [Time] Conditions/@NotOnOrAfter
      # @param clock_drift [Numeric] tolerated IdP clock skew (seconds)
      # @param now [Time] injectable clock for tests
      # @return [Boolean] true when NotOnOrAfter is beyond
      #   now + MAX_LIFETIME + clock_drift
      # @raise [ArgumentError] when not_on_or_after is not a Time
      def lifetime_exceeded?(not_on_or_after, clock_drift: 0, now: Time.now)
        raise ArgumentError, 'not_on_or_after must be a Time' unless not_on_or_after.is_a?(Time)

        (not_on_or_after - now) > MAX_LIFETIME + clock_drift.to_f.abs
      end

      # @return [Integer] seconds, within MIN_TTL..max_ttl_for(clock_drift)
      # @raise [ArgumentError] when not_on_or_after is not a Time
      def ttl_for(not_on_or_after, clock_drift: 0, now: Time.now)
        raise ArgumentError, 'not_on_or_after must be a Time' unless not_on_or_after.is_a?(Time)

        remaining = (not_on_or_after - now).ceil + clock_drift.to_f.ceil
        remaining.clamp(MIN_TTL, max_ttl_for(clock_drift))
      end

      # The longest key an accepted assertion can need: MAX_LIFETIME + drift
      # of remaining validity (the `lifetime_exceeded?` bound) plus the drift
      # added on top for the gem's acceptance window.
      #
      # @return [Integer] seconds
      def max_ttl_for(clock_drift)
        MAX_LIFETIME + (2 * clock_drift.to_f.abs.ceil)
      end
    end
  end
end
