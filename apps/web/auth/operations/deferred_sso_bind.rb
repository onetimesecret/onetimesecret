# apps/web/auth/operations/deferred_sso_bind.rb
#
# frozen_string_literal: true

require 'onetime/session/sidecar'

require_relative 'bind_sso_identity'

#
# Carries an ALREADY-AUTHORIZED SSO identity bind across the MFA hand-off
# (#3877 / #3840 Phase 4.A) — the interstitial's deferred-bind completion.
#
# ## Why this exists
#
# The password-challenge interstitial (Auth::Routes::LinkSso) may not bind the
# (provider, issuer, uid) identity when the password login leaves a second
# factor pending: SSO logins are MFA-EXEMPT (DetectMfaRequirement bypasses MFA
# for via_omniauth: true), so a row bound before the second factor completes
# would itself be an MFA-bypassing login path. Phase 3 therefore SKIPPED the
# bind for MFA accounts — closing the bypass but leaving the feature inert for
# them (the user re-hits the interstitial on every SSO sign-in).
#
# This operation completes that deferred bind AFTER the second factor succeeds,
# so an MFA account that authenticates through the interstitial ends up linked
# exactly like a non-MFA account:
#
#   1. `.defer`    — the interstitial stashes the pending bind for the partial
#                    MFA session (alongside PrepareMfaSession's awaiting_mfa
#                    state). The password has ALREADY been verified and the
#                    single-use challenge token ALREADY consumed by this point;
#                    the stash carries the authorization forward, it does not
#                    grant it.
#   2. `.complete` — the after_two_factor_authentication hook (hooks/mfa.rb)
#                    consumes the stash and performs the bind via the shared
#                    BindSsoIdentity primitive.
#
# ## Storage contract (#3858)
#
# The stash is a SessionSidecar explicit-use field — the sso_connect_intent
# pattern — NOT a field in the session blob:
#
#   sidecar:<sid>:link_sso_pending_bind   (encrypted, sid/field-bound, TTL 900s)
#
# holding the string-keyed bind tuple:
#
#   { 'account_id' => '42', 'provider' => 'oidc',
#     'issuer' => 'https://...', 'uid' => 'sub-123' }
#
# Living there instead of in the blob buys the two properties the blob could
# not provide (and closes the distributed session-key hand-off this class used
# to coordinate across the route and two hooks):
#
#   - BOUNDED IN TIME: the key's 900s TTL matches awaiting_mfa's MFA
#     completion window (SessionSidecar::FIELDS), so an ABANDONED half-done
#     MFA login expires the pending bind with the window instead of leaving
#     it live for the session blob's full 24h.
#   - ATOMIC SINGLE-USE: `.complete` consumes the key via SessionSidecar's
#     GETDEL, so exactly one caller can ever observe the stash — single-use
#     is enforced at the store, not by a Ruby delete-then-act sequence.
#
# TIMING (load-bearing): `.defer` must run with the FINAL sid of the login —
# Rodauth's login_session RE-KEYS the session (the app's clear_session
# override destroys it, minting a new sid), so a stash written before it
# would key to the destroyed sid and never be found. The interstitial defers
# inside the block it passes to rodauth.login('password'), which Rodauth
# yields between login_session (sid now final) and after_login (whose stale-
# prediction self-heal in hooks/login.rb is the earliest reader). The sid is
# then stable through the MFA hand-off — two_factor_authenticate never
# re-keys the session — so the MFA-verify request presents the same sid.
#
# TRIPWIRE for that stability assumption: `.complete` cannot log a missing
# stash (:none is its overwhelmingly common, legitimate outcome), so a future
# refactor that re-keys sessions MID-flow would strand the hand-off silently
# — except that the field is registered destroy_warn: true, and the session
# middleware's delete_session warns whenever it destroys a session still
# holding a live pending bind (Onetime::SessionSidecar#inflight_fields).
#
# ## Security model
#
#   - The stash is NOT an authorization: it can only be written by the
#     interstitial AFTER the existing password verified (and any prior session
#     content was destroyed by login_session moments earlier). It lives in an
#     encrypted, sid/field-bound sidecar envelope, out of the client's reach;
#     a value replayed under another sid decodes as absent.
#   - SINGLE-USE: `.complete` consumes the stash atomically BEFORE attempting
#     the bind, so an error can never leave a retryable pending bind behind.
#   - ACCOUNT-BOUND: the stash snapshots the account the password proved; if the
#     account completing the second factor differs, the bind is refused
#     (:mismatch) — defence-in-depth against a re-keyed session.
#   - FAIL-CLOSED, NEVER fails the login: the bind is best-effort by contract
#     (audit-and-skip). A lost or expired stash means no bind — the user
#     simply remains unlinked and can link later via Connected Identities —
#     so `.defer` swallows storage failures rather than aborting a login whose
#     password already verified. MFA has already succeeded when `.complete`
#     runs and there is no error surface to return to the user, so :conflict /
#     :mismatch are audit-and-skip outcomes (the BindSsoIdentity contract for
#     post-authentication callers).
#
# Returns from `.complete`:
#   :none     — no stash present (every login that didn't come through the
#               interstitial's deferred branch; the overwhelmingly common case)
#   :ok       — identity bound (or already present for this account — idempotent)
#   :conflict — the (provider, issuer, uid) row belongs to a DIFFERENT account;
#               nothing bound (audit-and-skip)
#   :mismatch — the authenticated account differs from the one the stash
#               snapshotted; nothing bound (audit-and-skip)
#
module Auth
  module Operations
    class DeferredSsoBind
      # The SessionSidecar registry field for the pending-bind payload.
      # Written only by `.defer` (from the interstitial's login block) and
      # consumed only by `.complete` (from the MFA-success hook / the
      # after_login self-heal).
      FIELD = 'link_sso_pending_bind'

      class << self
        # Stash a pending bind for the (already re-keyed) login session.
        #
        # BEST-EFFORT: a storage failure is logged and swallowed — the login
        # (whose password already verified) must proceed; the user just stays
        # unlinked this round (fail-closed) and re-hits the interstitial on
        # their next SSO sign-in.
        #
        # @param sid [String] the session id — read it AFTER login_session has
        #   run (inside the rodauth.login block), or the login-time re-key
        #   strands the stash under the destroyed sid
        # @param account_id [Integer, String] the account the password proved
        # @param provider [String] OmniAuth provider name
        # @param issuer [String, nil] resolved IdP issuer; nil → '' sentinel
        # @param uid [String] provider-scoped subject id
        # @return [Boolean] whether the stash was written
        def defer(sid:, account_id:, provider:, issuer:, uid:, logger: nil, dbclient: nil, codec: nil)
          logger ||= default_logger
          payload  = {
            'account_id' => account_id.to_s,
            'provider' => provider.to_s,
            'issuer' => issuer.to_s,
            'uid' => uid.to_s,
          }

          # write returns the effective TTL, or nil when no key was written
          # (a sid that fails the sidecar's format guard).
          written = !Onetime::SessionSidecar.write(
            sid, FIELD, payload, dbclient: dbclient, codec: codec
          ).nil?
          unless written
            logger.warn 'Deferred SSO bind not stashed: session id unavailable',
              account_id: account_id,
              provider: provider
          end
          written
        rescue StandardError => ex
          logger.warn 'Deferred SSO bind not stashed: sidecar write failed',
            account_id: account_id,
            provider: provider,
            error: ex.message,
            error_class: ex.class.name
          false
        end

        # Consume the stash (atomic single-use) and complete the bind for the
        # account that just fully authenticated.
        #
        # @param db [Sequel::Database] the auth database
        # @param sid [String] the session id carrying the sidecar stash
        # @param account_id [Integer, String] the account that completed the
        #   second factor (rodauth.account_id in the hook)
        # @param logger [Logger, nil]
        # @return [:none, :ok, :conflict, :mismatch]
        def complete(db:, sid:, account_id:, logger: nil, dbclient: nil, codec: nil)
          new(
            db: db,
            sid: sid,
            account_id: account_id,
            logger: logger,
            dbclient: dbclient,
            codec: codec,
          ).complete
        end

        def default_logger
          Onetime.get_logger('Auth::DeferredSsoBind')
        end
      end

      def initialize(db:, sid:, account_id:, logger: nil, dbclient: nil, codec: nil)
        @db         = db
        @sid        = sid
        @account_id = account_id
        @logger     = logger || self.class.default_logger
        @dbclient   = dbclient
        @codec      = codec
      end

      # @return [:none, :ok, :conflict, :mismatch]
      def complete
        # SINGLE-USE, ATOMIC: GETDEL at the store, so no outcome — including
        # an exception from the insert below — leaves a retryable pending bind
        # behind, and two concurrent completions can never both see the stash.
        # nil covers absent, expired, tampered, and sid-binding-mismatch alike.
        pending = Onetime::SessionSidecar.consume(@sid, FIELD, dbclient: @dbclient, codec: @codec)
        return :none unless well_formed?(pending)

        # ACCOUNT-BOUND: bind only onto the account the password proved. The
        # stash and the just-authenticated account can only disagree if the
        # session was re-keyed between the hand-off and the second factor —
        # refuse and audit, never bind across accounts.
        unless pending['account_id'].to_s == @account_id.to_s
          @logger.warn 'Deferred SSO bind skipped: authenticated account does not match stash',
            authenticated_account_id: @account_id,
            stashed_account_id: pending['account_id'],
            provider: pending['provider']
          return :mismatch
        end

        result = BindSsoIdentity.call(
          db: @db,
          account_id: @account_id,
          provider: pending['provider'],
          issuer: pending['issuer'],
          uid: pending['uid'],
        )

        if result == :conflict
          # The (provider, issuer, uid) row belongs to a different account.
          # MFA already succeeded and there is no error surface here, so this
          # is audit-and-skip (BindSsoIdentity's post-authentication caller
          # contract) — never raise, never fail the login.
          @logger.warn 'Deferred SSO bind skipped: identity owned by a different account',
            account_id: @account_id,
            provider: pending['provider']
        else
          @logger.info 'Deferred SSO identity bind completed after second factor',
            account_id: @account_id,
            provider: pending['provider']
        end

        result
      end

      private

      # A usable stash is a hash carrying the full bind tuple. Anything else
      # (nil, legacy junk, partial writes) is discarded silently — the key has
      # already been consumed above, so malformed data cannot linger.
      def well_formed?(pending)
        pending.is_a?(Hash) &&
          !pending['provider'].to_s.empty? &&
          !pending['uid'].to_s.empty? &&
          !pending['account_id'].to_s.empty?
      end
    end
  end
end
