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
#   POST /auth/link-sso         → verify existing password, bind identity, log in
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
      #                      one snapshotted at mint (defence-in-depth)
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

            # SINGLE-USE: consume the token NOW, before verifying the password, so
            # a token is worth exactly one guess (see the security note above).
            challenge.delete!

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

            # Bind the (provider, issuer, uid) identity to the proven account.
            # Shape mirrors omniauth_identity_insert_hash
            # (config/features/omniauth.rb): { account_id, provider, uid, issuer }.
            bind_sso_identity(challenge, account_id)

            # Verified credential -> clear the throttle so the just-linked user is
            # not held under a stale per-IP lockout on their next password login
            # (same keys as a normal successful login would clear).
            clear_login_rate_limit!(login, client_ip)

            auth_logger.warn 'SSO identity linked via password challenge',
              {
                account_id: account_id,
                provider: challenge.provider,
              }

            # Establish the session through Rodauth's proven login machinery.
            # login('password') runs before_login/login_session/after_login (Redis
            # session blob via SyncSession, active_sessions, MFA detection) and
            # then throws Rodauth's JSON login response (200 { success: ... },
            # plus mfa_required / billing_redirect when applicable) — exactly the
            # shape POST /auth/login returns, which the SPA already handles.
            rodauth.login('password')
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

      # Insert the identity row for the proven account, issuer-scoped and
      # idempotent. A concurrent bind that already inserted the row (unique index
      # on provider, issuer, uid) is treated as success.
      def bind_sso_identity(challenge, account_id)
        ds      = rodauth.db[:account_identities]
        already = ds.where(
          provider: challenge.provider,
          issuer: challenge.issuer.to_s,
          uid: challenge.uid,
        ).any?
        return if already

        ds.insert(
          account_id: account_id,
          provider: challenge.provider,
          uid: challenge.uid,
          issuer: challenge.issuer.to_s,
        )
      rescue Sequel::UniqueConstraintViolation
        nil
      end
    end
  end
end
