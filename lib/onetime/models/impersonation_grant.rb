# lib/onetime/models/impersonation_grant.rb
#
# frozen_string_literal: true

require 'securerandom'

module Onetime
  # ImpersonationGrant — a single-use, short-lived capability token that an
  # authorized operator redeems on the WEB surface to open an impersonation
  # session as a target customer, for support/incident response.
  #
  # ## Why a grant, not a CLI-minted session (the load-bearing decision)
  #
  # A logged-in web session is not a thing the CLI can safely fabricate. It is
  # populated inside the HTTP request lifecycle by Auth::Operations::SyncSession
  # (full mode, off Rodauth's after_login) or
  # Core::Logic::Authentication::AuthenticateSession (simple mode): both need a
  # live Rack::Session, the request object, and — in full mode — Rodauth, which
  # only mounts when mode=full. A CLI process has none of these. Forging a
  # session blob directly (writing an encrypted `session:<sid>` value out of
  # band) would sidestep every one of those code paths and produce an
  # unauditable, un-revocable, un-marked "real login" indistinguishable from the
  # customer's own — exactly what an impersonation feature must NOT be.
  #
  # So the CLI/Operation ISSUES this grant and records the audit event; the WEB
  # surface REDEEMS it into a session that it marks as impersonated. The grant is
  # the auditable, revocable, time-boxed primitive; session minting stays where
  # the session infrastructure already lives.
  #
  # This mirrors {Onetime::SsoLinkChallenge}: a Familia-expiring, delete-on-consume
  # capability that carries a decision across a surface boundary.
  #
  # ## Single-use in time (delete-on-consume + short TTL)
  #
  # The token is the Redis key and self-expires after its TTL. {#consume!} DELETEs
  # the key and only returns the payload when its own DEL won the race (Redis DEL
  # is atomic), so a grant is redeemable exactly ONCE even under two concurrent
  # redemptions. Revocable before use: delete the key.
  #
  # ## Bearer-token vs correlation id (do not conflate)
  #
  # `token` is a BEARER CREDENTIAL — possession is redemption. It must never be
  # written to a log or to the audit trail (the audit trail is colonel-readable;
  # a token sitting there within its TTL is a redeemable capability). `grant_id`
  # is a distinct, non-secret correlation id: it is what the audit event records
  # so an operator can tie a redemption back to its issuance WITHOUT the trail
  # carrying the capability itself.
  #
  # ## Not the authorization boundary
  #
  # Possession proves only that SOMEONE ran the issuing Operation. The redemption
  # endpoint MUST independently verify the REDEEMER is an authorized operator
  # (colonel) before it establishes the impersonation session — the grant carries
  # `actor` for the audit trail, never as the authorization to redeem.
  class ImpersonationGrant < Familia::Horreum
    feature :expiration

    prefix :impersonation_grant
    identifier_field :token

    # Default redemption window: tight on purpose. Long enough for an operator to
    # carry the token to the web surface, short enough that an abandoned/leaked
    # grant is dead within minutes.
    DEFAULT_TTL = 120

    # TTL floor/ceiling. A caller-supplied TTL is clamped into this range so no
    # adapter can widen the window past the hard ceiling or collapse it to zero.
    MIN_TTL = 30
    MAX_TTL = 600

    default_expiration DEFAULT_TTL

    field :token         # opaque single-use BEARER id; identifier and Redis key
    field :grant_id      # non-secret correlation id, safe to log/audit
    field :target_extid  # PUBLIC id of the impersonated customer (the subject)
    field :target_email  # display only; who the operator will be acting as
    field :actor         # PUBLIC id of the REAL operator (extid/email) — never objid
    field :reason        # mandatory operator-supplied justification
    field :created       # epoch float, mint time

    class << self
      # Mint and persist a grant with its TTL.
      #
      # @param target_extid [String] PUBLIC id of the customer to impersonate
      # @param actor [String] PUBLIC id of the REAL operator (extid/email)
      # @param reason [String] operator-supplied justification
      # @param target_email [String, nil] display-only email of the target
      # @param ttl [Integer] grant lifetime in seconds (clamped to MIN/MAX)
      # @return [ImpersonationGrant] persisted grant; #token is the capability
      def issue(target_extid:, actor:, reason:, target_email: nil, ttl: DEFAULT_TTL)
        ttl   = clamp_ttl(ttl)
        grant = new(
          token: SecureRandom.urlsafe_base64(32),
          grant_id: SecureRandom.uuid,
          target_extid: target_extid.to_s,
          target_email: target_email.to_s,
          actor: actor.to_s,
          reason: reason.to_s,
          created: Familia.now.to_f,
        )
        grant.save
        # Apply the (possibly per-issue) TTL after save; default_expiration is the
        # fallback but issue may narrow/widen within the clamp.
        grant.update_expiration(expiration: ttl)
        grant
      end

      # Clamp a caller-supplied TTL into [MIN_TTL, MAX_TTL]. A non-positive or
      # unparseable value falls back to DEFAULT_TTL.
      #
      # @param ttl [Integer, String, nil]
      # @return [Integer]
      def clamp_ttl(ttl)
        ttl = ttl.to_i
        return DEFAULT_TTL if ttl <= 0

        ttl.clamp(MIN_TTL, MAX_TTL)
      end
    end

    # Atomically claim and destroy this grant. Snapshots the fields, then DELETEs
    # the key; returns the frozen snapshot ONLY when this call's DEL won (count
    # positive). Under two concurrent redemptions exactly one caller sees a
    # positive count — the loser (and a caller of an already-consumed/expired
    # grant) gets nil. Single-use is enforced HERE, not by the caller.
    #
    # @return [Hash, nil] frozen payload snapshot on success, nil if already used
    def consume!
      snapshot = snapshot_payload
      claimed  = delete! # => dbclient.del(dbkey), the integer key count
      return nil unless claimed.to_i.positive?

      snapshot
    end

    # Non-secret projection for a redemption interstitial. Deliberately OMITS
    # `token` (the capability) — a caller that already holds the token does not
    # need it echoed, and nothing that renders this should be able to leak it.
    def to_display
      { grant_id: grant_id, target_email: target_email, actor: actor, reason: reason }
    end

    private

    def snapshot_payload
      {
        token: token,
        grant_id: grant_id,
        target_extid: target_extid,
        target_email: target_email,
        actor: actor,
        reason: reason,
        created: created,
      }.freeze
    end
  end
end
