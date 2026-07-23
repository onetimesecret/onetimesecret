# apps/web/auth/operations/deferred_sso_bind.rb
#
# frozen_string_literal: true

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
#   1. `.defer`    — the interstitial stashes the pending bind into the partial
#                    MFA session (alongside PrepareMfaSession's awaiting_mfa
#                    state). The password has ALREADY been verified and the
#                    single-use challenge token ALREADY consumed by this point;
#                    the stash carries the authorization forward, it does not
#                    grant it.
#   2. `.complete` — the after_two_factor_authentication hook (hooks/mfa.rb)
#                    consumes the stash and performs the bind via the shared
#                    BindSsoIdentity primitive.
#
# ## Session contract
#
# The payload lives under SESSION_KEY as a STRING-KEYED hash — the session blob
# is JSON-serialized into Redis between the login request and the MFA-verify
# request (lib/onetime/session.rb), so symbol keys would not round-trip:
#
#   { 'account_id' => '42', 'provider' => 'oidc',
#     'issuer' => 'https://...', 'uid' => 'sub-123' }
#
# TIMING (load-bearing): Rodauth's login_session CLEARS the session (the app's
# clear_session override destroys it) before after_login runs, so the stash must
# be written AFTER login_session — the interstitial writes it inside the block
# it passes to rodauth.login('password'), which Rodauth yields between
# login_session and after_login. From there it survives the MFA hand-off:
# two_factor_authenticate does not clear the session (it only appends to
# authenticated_by), the same mechanism awaiting_mfa relies on.
#
# ## Security model
#
#   - The stash is NOT an authorization: it can only be written by the
#     interstitial AFTER the existing password verified (and any prior session
#     content was destroyed by login_session moments earlier). It lives in the
#     server-side encrypted+HMAC'd session blob, out of the client's reach.
#   - SINGLE-USE: `.complete` deletes the stash BEFORE attempting the bind, so
#     an error can never leave a retryable pending bind behind.
#   - ACCOUNT-BOUND: the stash snapshots the account the password proved; if the
#     account completing the second factor differs, the bind is refused
#     (:mismatch) — defence-in-depth against a re-keyed session.
#   - NEVER fails the login: MFA has already succeeded when `.complete` runs and
#     there is no error surface to return to the user, so :conflict / :mismatch
#     are audit-and-skip outcomes (the BindSsoIdentity contract for
#     post-authentication callers). The user simply remains unlinked and can
#     link later via Connected Identities.
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
      # Session key for the pending-bind payload. Written only by `.defer`
      # (from the interstitial's login block) and consumed only by `.complete`
      # (from the MFA-success hook).
      SESSION_KEY = 'link_sso_pending_bind'

      class << self
        # Stash a pending bind into the (already re-keyed) login session.
        #
        # @param session [Hash] the Rack session — call AFTER login_session has
        #   run (inside the rodauth.login block), or the login-time
        #   clear_session wipes the stash
        # @param account_id [Integer, String] the account the password proved
        # @param provider [String] OmniAuth provider name
        # @param issuer [String, nil] resolved IdP issuer; nil → '' sentinel
        # @param uid [String] provider-scoped subject id
        def defer(session:, account_id:, provider:, issuer:, uid:)
          session[SESSION_KEY] = {
            'account_id' => account_id.to_s,
            'provider'   => provider.to_s,
            'issuer'     => issuer.to_s,
            'uid'        => uid.to_s,
          }
        end

        # Consume the stash (single-use) and complete the bind for the account
        # that just fully authenticated.
        #
        # @param db [Sequel::Database] the auth database
        # @param session [Hash] the Rack session carrying the stash
        # @param account_id [Integer, String] the account that completed the
        #   second factor (rodauth.account_id in the hook)
        # @param logger [Logger, nil]
        # @return [:none, :ok, :conflict, :mismatch]
        def complete(db:, session:, account_id:, logger: nil)
          new(db: db, session: session, account_id: account_id, logger: logger).complete
        end
      end

      def initialize(db:, session:, account_id:, logger: nil)
        @db         = db
        @session    = session
        @account_id = account_id
        @logger     = logger || Onetime.get_logger('Auth::DeferredSsoBind')
      end

      # @return [:none, :ok, :conflict, :mismatch]
      def complete
        # SINGLE-USE: remove the stash up front so no outcome — including an
        # exception from the insert — leaves a retryable pending bind behind.
        pending = @session.delete(SESSION_KEY)
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
      # already been deleted above, so malformed data cannot linger.
      def well_formed?(pending)
        pending.is_a?(Hash) &&
          !pending['provider'].to_s.empty? &&
          !pending['uid'].to_s.empty? &&
          !pending['account_id'].to_s.empty?
      end
    end
  end
end
