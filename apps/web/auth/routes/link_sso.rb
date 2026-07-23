# apps/web/auth/routes/link_sso.rb
#
# frozen_string_literal: true

require 'onetime/security/login_rate_limiter'

#
# JSON API for the SSO sign-in interstitial (#3840 Phase 3 / #3838 item 1b).
#
# When an UNAUTHENTICATED SSO sign-in resolves to an EXISTING account that has a
# password, account_from_omniauth (config/hooks/omniauth.rb) mints a single-use
# Onetime::SsoLinkChallenge and redirects the browser to the SPA interstitial
# (/link-sso/:token). These endpoints back that page:
#
#   GET  /auth/link-sso/:token  → { provider, email }         (display only)
#   POST /auth/link-sso         → verify existing password, log in, bind on full auth
#
# SECURITY MODEL (the invariant: email may LOCATE, only a credential may BIND):
#   - The challenge token is NOT proof of ownership — it only proves someone
#     completed an SSO round-trip for this email. The EXISTING PASSWORD is the
#     credential that authorizes the bind.
#   - The token is SINGLE-USE: POST deletes it up front (before verifying the
#     password), so each token is good for exactly one attempt. This is
#     load-bearing — Auth::Config.valid_login_and_password? is an internal
#     request that bypasses Rodauth's lockout counters, so without one-shot
#     consumption a minted token would be an unbounded (TTL-window) password
#     oracle with no lockout. One guess per full IdP round-trip is the bound.
#   - RATE LIMITED (#3840 Phase 3 review, Finding 2): single-use caps guesses
#     per token, but NOT in aggregate across freshly minted tokens — wherever the
#     IdP does not strongly bind email to a vetted subject (unverified-email OIDC
#     / public providers) an attacker can mint token after token, one guess each,
#     with no lockout (the internal-request password check does not increment
#     Rodauth's counters). POST therefore runs the canonical
#     Onetime::Security::LoginRateLimiter (email + client IP) BEFORE consuming the
#     token, and records each wrong guess — closing the residual aggregate oracle.
#   - On success the session is established by Rodauth's OWN login machinery
#     (rodauth.login('password')) — NOT hand-rolled — so after_login runs
#     (Redis session blob via SyncSession, active_sessions registration, MFA
#     detection). That blob, not the Rodauth SQL row, is the real app auth gate.
#   - MFA-SAFE BIND (#3840 review, Item 1): the identity is bound ONLY when the
#     password login FULLY authenticates. If the account has a pending second
#     factor, the bind is DEFERRED — login still proceeds and returns mfa_required
#     (the SAME body POST /auth/login emits), but no identity is linked this round.
#     Binding before 2FA would attach an MFA-EXEMPT SSO login path (SSO logins
#     bypass MFA) to an account whose owner never passed the second factor — a
#     password-only attacker could then sign in via SSO and defeat MFA. The
#     deferred bind is stashed in a short-TTL SessionSidecar key bound to the
#     partial MFA session's sid (DeferredSsoBind.defer, #3858) and completed by
#     after_two_factor_authentication once the second factor succeeds (#3877 /
#     Phase 4.A), so MFA accounts end up linked exactly like non-MFA accounts —
#     just one factor later.
#   - PLATFORM-only: challenges are minted solely on the platform callback path,
#     so the tenant surface is never offered this interstitial (#3849).
#
module Auth
  module Routes
    module LinkSso
      # Reuse the canonical credential-submission throttle. It is designed for
      # exactly this gap: an internal-request password verify with NO Rodauth
      # lockout. Two-tier (per-email+IP tight lock at MAX_ATTEMPTS, per-email
      # global backstop for IP-rotators), sharing the SAME Redis keys as normal
      # password login so the throttle is unified across both surfaces. Included
      # here so its check/record/clear methods are available in the route block
      # (LinkSso is included into Auth::Router).
      include Onetime::Security::LoginRateLimiter

      # Error codes returned to the SPA (LinkSso.vue maps these to copy + the
      # Phase 2 settings pointer /account/settings/security/connections):
      #   invalid_request — token or password missing
      #   link_expired    — token missing / already consumed / expired, or the
      #                      located account vanished between mint and POST
      #   invalid_password— the existing password did not verify (token consumed)
      #   link_conflict   — the email now resolves to a different account than the
      #                      one snapshotted at mint, OR the (provider,issuer,uid)
      #                      is already bound to a different account (defence-in-depth)
      #   link_rate_limited— too many password attempts for this account/IP (429);
      #                      carries retry_after seconds
      def handle_link_sso_routes(r)
        r.on 'link-sso' do
          # GET /auth/link-sso/:token — display context for the interstitial.
          # Returns ONLY the provider name and claimed email; never the account
          # id, uid, or issuer. Missing/consumed/expired token → 404.
          r.get String do |token|
            challenge = Onetime::SsoLinkChallenge.load(token)
            unless challenge
              response.status = 404
              next { error: 'This linking request is no longer valid.', error_code: 'link_expired' }
            end

            response.headers['Content-Type'] = 'application/json'
            challenge.to_display
          rescue StandardError => ex
            auth_logger.error 'Error loading SSO link challenge', { exception: ex }
            response.status = 500
            { error: 'Failed to load linking request' }
          end

          # POST /auth/link-sso — verify the existing password, bind the identity,
          # and establish the login session. Body: { token, password }.
          r.post do
            # Rodauth's JSON feature parses request bodies only for its OWN
            # routes; this is a custom Roda route, so parse the JSON body here
            # (falling back to form/query params).
            params   = link_sso_params(request)
            token    = params[:token]
            password = params[:password]

            if token.empty? || password.empty?
              response.status = 400
              next { error: 'Token and password are required.', error_code: 'invalid_request' }
            end

            challenge = Onetime::SsoLinkChallenge.load(token)
            unless challenge
              response.status = 401
              next {
                error: 'This linking request has expired. Please sign in with SSO again.',
                error_code: 'link_expired',
              }
            end

            login     = challenge.email
            client_ip = request.ip

            # RATE LIMIT (#3840 Phase 3 review, Finding 2) — gate BEFORE consuming
            # the token or verifying the password. valid_login_and_password? is a
            # Rodauth INTERNAL request and does NOT increment Rodauth's lockout
            # counters, so single-use alone caps per-token but not in aggregate
            # across freshly minted tokens. Keyed on the located account's email +
            # client IP via the canonical LoginRateLimiter. Raises
            # Onetime::LimitExceeded when locked -> 429 (rescued below, before the
            # generic StandardError rescue that would otherwise mask it as a 500).
            check_login_rate_limit!(login, client_ip)

            # SINGLE-USE (atomic — #3840 review, Item 2): consume the token NOW,
            # before verifying the password, so a token is worth exactly one guess.
            # #delete! returns the Redis DEL count; because DEL is atomic, exactly
            # ONE of two concurrent POSTs gets 1 (the winner) and the loser gets 0.
            # A 0 means the token was already spent by a racing request (or expired
            # between load and here) -> reject as spent, closing the load-then-delete
            # TOCTOU that would otherwise let both racers reach the password check.
            unless challenge.delete! == 1
              response.status = 401
              next {
                error: 'This linking request has expired. Please sign in with SSO again.',
                error_code: 'link_expired',
              }
            end

            # Verify the EXISTING password via Rodauth's internal request. This
            # routes through the password_match? override (Redis→Rodauth password
            # migration is transparent). Raises Rodauth::InternalRequestError on a
            # non-match (mirrors apps/api/account/logic/account/update_password.rb).
            password_ok = begin
              Auth::Config.valid_login_and_password?(login: login, password: password)
            rescue Rodauth::InternalRequestError
              false
            end

            unless password_ok
              # Count the failed guess toward the lockout so repeated wrong
              # passwords (across freshly minted tokens) eventually trip the limit.
              record_failed_login_attempt!(login, client_ip)
              response.status = 401
              next { error: 'Incorrect password.', error_code: 'invalid_password' }
            end

            # Re-locate the account by the verified login and load it onto the
            # rodauth instance so login('password') can establish the session.
            unless rodauth.account_from_login(login)
              response.status = 401
              next { error: 'This linking request is no longer valid.', error_code: 'link_expired' }
            end

            account_id = rodauth.account_id

            # Defence-in-depth: the account located by login now must match the one
            # snapshotted at mint. A mismatch (email re-pointed between mint and
            # POST) must never bind onto a different account.
            if challenge.account_id.to_s != account_id.to_s
              response.status = 409
              next { error: 'This linking request could not be completed.', error_code: 'link_conflict' }
            end

            # LOGIN-FIRST, BIND-ON-FULL-AUTH (#3840 review, Item 1).
            #
            # Rodauth's login('password') THROWS its JSON response (Roda :halt) and
            # never returns to this route, so we cannot inspect the login result
            # after the fact and then bind. Instead we make the SAME MFA decision
            # the after_login hook makes (hooks/login.rb — a pure function of the
            # located account's stored factors, via_omniauth: false) HERE, and gate
            # the bind on it. Security-equivalent to "login, then bind only when
            # fully authenticated": we bind ONLY when no second factor is pending.
            #
            # WHY: SSO logins are MFA-EXEMPT (DetectMfaRequirement bypasses MFA for
            # via_omniauth: true). Binding the (provider, issuer, uid) row before a
            # second factor is satisfied would leave an MFA-bypassing SSO login path
            # attached to the account — a password-only attacker who cannot pass the
            # victim's OTP could bind their own IdP identity and then sign in via
            # SSO, defeating MFA. So for an MFA account we DEFER the bind: the login
            # below proceeds to the OTP step (emits mfa_required, unchanged), the
            # identity stays UNLINKED this round, and the stashed bind is completed
            # by after_two_factor_authentication once the second factor succeeds
            # (#3877). Moot for default installs (MFA off) but load-bearing for
            # AUTH_MFA_ENABLED deployments.
            deferred_bind = nil
            if link_sso_second_factor_pending?(account_id)
              # DEFERRED BIND (#3877 / Phase 4.A): the password HAS verified, so
              # the bind is authorized — only its timing moves. Snapshot the
              # challenge tuple here (the single-use token is already consumed;
              # this local is the last place it exists) and stash it INSIDE the
              # login block below as a short-TTL SessionSidecar key bound to
              # the partial MFA session's sid (#3858), to be consumed by
              # after_two_factor_authentication (hooks/mfa.rb), which completes
              # the bind once the second factor succeeds.
              deferred_bind = {
                account_id: account_id,
                provider: challenge.provider,
                issuer: challenge.issuer,
                uid: challenge.uid,
              }
              auth_logger.warn 'SSO link deferred: second factor pending, bind completes after MFA',
                {
                  account_id: account_id,
                  provider: challenge.provider,
                }
            else
              # Fully authenticated by password alone -> safe to bind now. Shared
              # bind primitive (#3840 Phase 4): idempotent, issuer-scoped insert
              # whose column shape mirrors omniauth_identity_insert_hash
              # (config/features/omniauth.rb): { account_id, provider, uid, issuer }.
              bind_result = Auth::Operations::BindSsoIdentity.call(
                db: rodauth.db,
                account_id: account_id,
                provider: challenge.provider,
                issuer: challenge.issuer,
                uid: challenge.uid,
              )
              if bind_result == :conflict
                # Item 3 defence-in-depth: the (provider, issuer, uid) row is already
                # owned by a DIFFERENT account. Never report success (that would log
                # the caller in as if the identity were theirs) — surface a conflict.
                response.status = 409
                next {
                  error: 'This linking request could not be completed.',
                  error_code: 'link_conflict',
                }
              end

              auth_logger.warn 'SSO identity linked via password challenge',
                {
                  account_id: account_id,
                  provider: challenge.provider,
                }
            end

            # Verified credential -> clear the throttle so the user is not held under
            # a stale per-IP lockout on their next password login (same keys a normal
            # successful login clears). Cleared in BOTH branches: the password was
            # correct regardless of the MFA outcome.
            clear_login_rate_limit!(login, client_ip)

            # Establish the session through Rodauth's proven login machinery.
            # login('password') runs before_login/login_session/after_login (Redis
            # session blob via SyncSession, active_sessions, MFA detection) and then
            # THROWS Rodauth's JSON login response — 200 { success: ... } for a
            # non-MFA account, or the SAME mfa_required body POST /auth/login returns
            # for an MFA account (authSuccessWithMfaSchema). The response passes
            # through unchanged; the SPA already handles both shapes.
            #
            # The block Rodauth yields runs between login_session and after_login —
            # the ONLY point that both sees the login's FINAL sid (login_session
            # destroys the previous session, minting a new sid; a stash keyed to
            # the old sid would never be found) and precedes after_login (whose
            # stale-prediction self-heal in hooks/login.rb is the earliest
            # reader). Stash the deferred bind there — a sid-bound SessionSidecar
            # key (#3858) — so after_two_factor_authentication can consume it.
            # Best-effort by contract: a failed stash write is logged inside
            # `.defer` and the login proceeds unlinked (fail-closed).
            rodauth.login('password') do
              if deferred_bind
                Auth::Operations::DeferredSsoBind.defer(
                  sid: session.id&.public_id, **deferred_bind,
                )
              end
            end
          rescue Onetime::LimitExceeded => ex
            # Must precede the generic StandardError rescue below (which would turn
            # this into a 500). Translate to the ADR-013-style 429 the SPA surfaces.
            auth_logger.warn 'SSO link rate limited', { retry_after: ex.retry_after }
            response.status                 = 429
            response.headers['Retry-After'] = ex.retry_after.to_s if ex.retry_after
            {
              error: 'Too many attempts. Please try again later.',
              error_code: 'link_rate_limited',
              retry_after: ex.retry_after,
            }
          rescue StandardError => ex
            auth_logger.error 'Error completing SSO link', { exception: ex }
            response.status = 500
            { error: 'Failed to complete linking' }
          end
        end
      end

      private

      # Extract { token, password } from a JSON body (Content-Type
      # application/json), falling back to form/query params. Returns string
      # values ('' when absent). Rewinds the input so nothing downstream is
      # surprised by a consumed body.
      def link_sso_params(request)
        raw = request.body&.read.to_s
        request.body.rewind if request.body.respond_to?(:rewind)

        parsed = begin
          raw.empty? ? {} : JSON.parse(raw)
        rescue JSON::ParserError
          {}
        end
        parsed = {} unless parsed.is_a?(Hash)

        {
          token: (parsed['token'] || request.params['token']).to_s,
          password: (parsed['password'] || request.params['password']).to_s,
        }
      end

      # Would completing this PASSWORD login leave a second factor pending? Mirrors
      # the after_login hook's MFA decision (hooks/login.rb) for via_omniauth: false
      # — a pure function of the located account's stored factors — evaluated HERE so
      # the identity bind can be gated on FULL authentication (Item 1). When the OTP
      # feature is not loaded (MFA disabled — the default), no second factor can be
      # pending, so this returns false and the bind proceeds. A read error propagates
      # to the POST handler's rescue (uniform with the unguarded MfaStateChecker call
      # in after_login) rather than binding without certainty of full auth.
      def link_sso_second_factor_pending?(account_id)
        return false unless rodauth.respond_to?(:otp_auth_route)

        mfa_state = Auth::Operations::MfaStateChecker.new(rodauth.db).check(account_id)
        Auth::Operations::DetectMfaRequirement.call(
          account_id: account_id,
          has_otp_secret: mfa_state.has_otp_secret,
          has_recovery_codes: mfa_state.has_recovery_codes,
          via_omniauth: false,
        ).requires_mfa?
      end
    end
  end
end
