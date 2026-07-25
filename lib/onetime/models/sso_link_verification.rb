# lib/onetime/models/sso_link_verification.rb
#
# frozen_string_literal: true

require 'securerandom'

module Onetime
  # SsoLinkVerification — a single-use, short-lived capability token that carries a
  # MAILBOX-PROOF SSO link across the email round-trip (#3840 Phase 4).
  #
  # ## Why this exists (sibling of SsoLinkChallenge, different proof)
  #
  # When an UNAUTHENTICATED SSO sign-in resolves to an EXISTING local account that
  # is PASSWORDLESS (no challengeable password), the H-3 refusal in
  # account_from_omniauth (apps/web/auth/config/hooks/omniauth.rb) would otherwise
  # dead-end the user at /signin?auth_error=account_exists_link_required. Phase 3's
  # SsoLinkChallenge cannot help here: it proves ownership by re-entering the
  # EXISTING PASSWORD, and this account has none.
  #
  # A passwordless account CAN still prove ownership: control of the on-file
  # mailbox — the same proof magic-link (email_auth) uses to authenticate. Phase 4
  # emails a single-use token to the ACCOUNT's on-file address; clicking it proves
  # mailbox control and authorizes binding the (provider, issuer, uid) identity.
  # This honours the invariant "email may LOCATE an account; only a demonstrated
  # credential may BIND" — mailbox control is the demonstrated credential.
  #
  # ## The token travels ONLY via email (security-load-bearing)
  #
  # The proof is MAILBOX control, so the token MUST reach the user only through the
  # emailed link — NEVER through the callback redirect URL. The OmniAuth callback
  # redirects the browser to a TOKEN-LESS informational state
  # (/signin?auth_notice=link_verification_sent); the token is delivered solely to
  # the on-file inbox. A caller who merely completed an SSO round-trip asserting the
  # victim's email therefore learns nothing that lets them consume the token.
  #
  # ## Single-use in time (delete-on-consume + short TTL)
  #
  # The token id is the Redis key. The record self-expires after DEFAULT_EXPIRATION
  # seconds (== 15 min, criterion 3), and POST /auth/sso-link-confirm DELETES it
  # (#delete!) as the atomic single-use gate BEFORE it binds. Mirrors the shipped
  # delete-on-consume patterns: SsoLinkChallenge, Customer#pending_plan_intent,
  # OrganizationMembership#accept!.
  #
  # ## Deltas vs SsoLinkChallenge (Phase 3)
  #
  #   - TTL is 900s (15 min), not 300s — a human must switch to their inbox, open
  #     the message, and click, which is slower than entering a password inline.
  #   - Adds `sid` — the id of the session that INITIATED the SSO round-trip. This
  #     is a SOFT (compare-and-warn) binding, NOT a hard gate: mailbox proof is
  #     inherently cross-device (the user may open the link on their phone), so a
  #     sid mismatch is logged for observability but never rejected.
  #   - Adds `password_watermark` — a snapshot of the account's
  #     Customer#last_password_update at issuance. Consume-time re-checks it and
  #     rejects if it advanced, so ANY credential change (password set/reset/change,
  #     which all stamp the watermark via Auth::Operations::UpdatePasswordMetadata)
  #     between issuance and click invalidates the token (criterion 3). This is a
  #     watermark comparison, not a token-enumeration sweep — no need to find and
  #     delete outstanding tokens on every credential change.
  #
  # ## Not the security boundary
  #
  # Possession of a token proves only that SOMEONE completed an SSO round-trip for
  # this email AND received the email at the on-file inbox. The mailbox delivery is
  # the boundary; account_id/email/watermark carried here are defence-in-depth
  # consistency checks re-verified at consume time (Auth::Operations::ConfirmSsoLink),
  # never the authorization to bind.
  class SsoLinkVerification < Familia::Horreum
    feature :expiration

    prefix :sso_link_verification
    identifier_field :token

    # 15 minutes — criterion 3's TTL ceiling. Covers the human email round-trip
    # (switch to inbox, open, click) while bounding the abandoned/guessing window.
    # Raw seconds (no TimeLiterals refinement needed), matching SsoLinkChallenge.
    DEFAULT_EXPIRATION = 900
    default_expiration DEFAULT_EXPIRATION

    field :token              # opaque single-use id; also the identifier and Redis key
    field :provider           # OmniAuth strategy name ('oidc', 'entra', ...) — display + bind
    field :issuer             # resolved issuer for issuer-scoped binding ('' sentinel allowed)
    field :uid                # IdP subject (sub) to bind
    field :email              # normalized on-file email that LOCATED the account — display + login
    field :account_id         # snapshotted account PK — defence-in-depth consistency check
    field :sid                # initiating session id — SOFT (compare-and-warn) binding
    field :password_watermark # Customer#last_password_update snapshot — credential-change guard

    class << self
      # Mint a new single-use verification token and persist it with its TTL.
      #
      # @param provider           [String, Symbol]  OmniAuth strategy name
      # @param uid                [String]          IdP subject identifier
      # @param email              [String]          normalized on-file email that located the account
      # @param account_id         [Integer, String] located account's primary key
      # @param sid                [String, nil]     initiating session id (soft-bound)
      # @param password_watermark [Integer, String] Customer#last_password_update at issuance
      # @param issuer             [String, nil]     resolved issuer ('' sentinel permitted)
      # @return [SsoLinkVerification] the persisted token (available as #token)
      def issue(provider:, uid:, email:, account_id:, sid: nil, password_watermark: 0, issuer: nil)
        verification = new(
          token: SecureRandom.urlsafe_base64(32),
          provider: provider.to_s,
          issuer: issuer.to_s,
          uid: uid.to_s,
          email: email.to_s,
          account_id: account_id.to_s,
          sid: sid.to_s,
          password_watermark: password_watermark.to_i.to_s,
        )
        verification.save
        verification
      end
    end

    # Display-only projection for GET /auth/sso-link-confirm/:token. Intentionally
    # omits uid, issuer, account_id, sid, and the watermark — the consent screen
    # only needs to NAME the requesting provider and echo the claimed email
    # (criterion 2); nothing else is safe to surface to a caller who merely holds
    # the token.
    def to_display
      { provider: provider, email: email }
    end
  end
end
