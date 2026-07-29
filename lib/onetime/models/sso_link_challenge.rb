# lib/onetime/models/sso_link_challenge.rb
#
# frozen_string_literal: true

require 'securerandom'

module Onetime
  # SsoLinkChallenge — a single-use, short-lived capability token that carries an
  # unauthenticated SSO sign-in across the password-challenge interstitial
  # (#3840 Phase 3 / #3838 item 1b).
  #
  # ## Why this exists
  #
  # When an UNAUTHENTICATED SSO sign-in resolves to an EXISTING local account that
  # already has a password, the H-3 refusal in account_from_omniauth
  # (apps/web/auth/config/hooks/omniauth.rb) would otherwise dead-end the user at
  # /signin?auth_error=account_exists_link_required. That refusal is correct for
  # SSO-only accounts (nothing to prove), but a password-holding account CAN prove
  # ownership: re-enter the existing password. Phase 3 offers an interstitial that
  # collects that password, verifies it, and only then binds the (provider, issuer,
  # uid) identity — honouring the invariant "email may LOCATE an account; only a
  # demonstrated credential may BIND".
  #
  # The bind cannot happen inside the OmniAuth callback (the password has not been
  # collected yet) and the callback-only auth-hash accessors (omniauth_uid,
  # resolved_issuer, ...) are gone by the time the password POST arrives. So the
  # callback SNAPSHOTS the decision into one of these records and redirects to the
  # interstitial carrying the token; the POST /auth/link-sso handler loads it back.
  #
  # ## Single-use in time (delete-on-consume + short TTL)
  #
  # The token id is the Redis key. The record self-expires after
  # DEFAULT_EXPIRATION seconds (one IdP round-trip), and POST /auth/link-sso
  # DELETES it (#delete!) before it even verifies the password — so a token is
  # good for exactly ONE attempt. This is deliberate and security-load-bearing:
  # Auth::Config.valid_login_and_password? does NOT run through the login route, so
  # it does NOT increment Rodauth's lockout counters. Consuming the token up front
  # means an attacker who mints a challenge (by completing an SSO round-trip that
  # asserts a victim's email) gets ONE password guess per full IdP round-trip, not
  # an unbounded 5-minute oracle. Mirrors the shipped delete-on-consume patterns:
  # Customer#pending_plan_intent (Auth::Config::Hooks::Billing.extract_pending_plan_intent)
  # and OrganizationMembership#accept! (one-shot token_lookup consume).
  #
  # ## Not the security boundary
  #
  # Possession of a token proves only that SOMEONE completed an SSO round-trip for
  # this email; it is NOT proof of account ownership. The password check in
  # POST /auth/link-sso is the boundary. The token carries account_id purely as a
  # defence-in-depth consistency check against the account re-located by email at
  # POST time — never as the authorization to bind.
  class SsoLinkChallenge < Familia::Horreum
    feature :expiration

    prefix :sso_link_challenge
    identifier_field :token

    # 5 minutes — comfortably covers one IdP round-trip plus entering a password,
    # short enough to bound the abandoned-challenge / guessing window. Raw seconds
    # (no TimeLiterals refinement needed), matching Onetime::SessionMetadata.
    DEFAULT_EXPIRATION = 300
    default_expiration DEFAULT_EXPIRATION

    field :token       # opaque single-use id; also the identifier and Redis key
    field :provider    # OmniAuth strategy name ('oidc', 'entra', ...) — display + bind
    field :issuer      # resolved issuer for issuer-scoped binding ('' sentinel allowed)
    field :uid         # IdP subject (sub) to bind
    field :email       # normalized email that LOCATED the account — display + login
    field :account_id  # snapshotted account PK — defence-in-depth consistency check

    class << self
      # Mint a new single-use challenge and persist it with its TTL.
      #
      # @param provider   [String, Symbol] OmniAuth strategy name
      # @param issuer     [String, nil]    resolved issuer ('' sentinel permitted)
      # @param uid        [String]         IdP subject identifier
      # @param email      [String]         normalized email that located the account
      # @param account_id [Integer, String] located account's primary key
      # @return [SsoLinkChallenge] the persisted challenge (token available as #token)
      def issue(provider:, uid:, email:, account_id:, issuer: nil)
        challenge = new(
          token: SecureRandom.urlsafe_base64(32),
          provider: provider.to_s,
          issuer: issuer.to_s,
          uid: uid.to_s,
          email: email.to_s,
          account_id: account_id.to_s,
        )
        challenge.save
        challenge
      end
    end

    # Display-only projection for GET /auth/link-sso/:token. Intentionally omits
    # uid, issuer, and account_id — the interstitial only needs to name the
    # provider and echo the claimed email; nothing else is safe to surface to an
    # unauthenticated caller who merely holds the token.
    def to_display
      { provider: provider, email: email }
    end
  end
end
