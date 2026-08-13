# apps/web/auth/routes/sso_link_confirm.rb
#
# frozen_string_literal: true

require 'onetime/security/login_rate_limiter'

require 'auth/lib/logging'
require 'auth/operations/confirm_sso_link'
require 'auth/operations/deferred_sso_bind'

require_relative 'json_body'
require_relative '../restrict_to'

#
# JSON API for the MAILBOX-PROOF SSO linking flow (#3840 Phase 4).
#
# When an UNAUTHENTICATED SSO sign-in resolves to an EXISTING PASSWORDLESS account,
# account_from_omniauth (config/hooks/omniauth.rb) issues a single-use
# Onetime::SsoLinkVerification, EMAILS the token to the account's on-file address,
# and redirects the browser to a TOKEN-LESS notice (/signin?auth_notice=
# link_verification_sent). The token never rides the callback redirect — it reaches
# the user only through the emailed link, so possessing it proves mailbox control.
# These endpoints back the confirm page the emailed link points at:
#
#   GET  /auth/sso-link-confirm/:token  → { provider, email }   (consent display)
#   POST /auth/sso-link-confirm         → consume token, bind identity, log in
#
# WHY GET IS DISPLAY-ONLY AND POST DOES THE MUTATION: the emailed link opens the
# SPA consent screen, which GETs the display context (provider + claimed email —
# criterion 2's consent copy) and only mutates on an explicit user action (the
# POST). A GET must stay side-effect-free: mail clients and link-preview bots
# prefetch GET URLs, and a mutating GET would let such a prefetch silently consume
# the single-use token before the user consents. The GET therefore NEVER consumes;
# the POST is the atomic single-use consume + bind.
#
# SECURITY MODEL (the invariant: email may LOCATE, only a demonstrated credential
# may BIND — here the credential is MAILBOX CONTROL):
#   - The token is delivered ONLY to the on-file inbox, so holding it is the proof.
#   - SINGLE-USE: the POST consumes the token atomically (#delete!) before binding,
#     so it is good for exactly one confirmation (Auth::Operations::ConfirmSsoLink).
#   - RATE LIMITED (#3840 PR #3900 review): single-use caps attempts per TOKEN, but
#     nothing bounded how many GUESSED tokens one client could probe. The POST runs
#     the canonical Onetime::Security::LoginRateLimiter keyed per CLIENT IP before
#     the op touches the token — see #sso_link_confirm_throttle_subject for why the
#     key differs from the interstitial's email+IP (a guessed token carries no email).
#   - CREDENTIAL-CHANGE INVALIDATION: the token snapshots the account's password
#     watermark; a change since issuance rejects it (:link_invalidated).
#   - MFA-SAFE BIND: when a second factor is pending the bind is DEFERRED (SSO paths
#     are MFA-exempt), but the login still proceeds to the OTP step.
#   - CONFIRM LOGS THE USER IN: the account is passwordless, and clicking the emailed
#     link proves mailbox control == the SAME proof magic-link (email_auth) uses to
#     authenticate. On success the session is established through Rodauth's OWN login
#     machinery (rodauth.login) — NOT hand-rolled — so after_login runs (Redis
#     session blob via SyncSession, active_sessions, MFA detection). The user lands
#     signed in and their newly linked SSO works next time.
#   - PLATFORM-only: verifications are issued solely on the platform callback path
#     (the tenant surface keeps the H-3 refusal), so this is never offered to tenants.
#
module Auth
  module Routes
    module SsoLinkConfirm
      # Canonical credential-submission throttle, here throttling token GUESSES per
      # client (see #sso_link_confirm_throttle_subject for the keying rationale).
      # Included so its check/record/clear methods are available in the route block
      # (SsoLinkConfirm is included into Auth::Router), mirroring LinkSso.
      include Onetime::Security::LoginRateLimiter

      # Shared body parser for the custom (non-Rodauth) routes; see json_body.rb.
      include Auth::Routes::JsonBody

      # Error codes returned to the SPA (SsoLinkConfirm.vue maps these to copy):
      #   invalid_request  — token missing from the POST body
      #   link_expired     — token missing / already consumed / expired, or the
      #                      snapshotted account vanished (or is no longer loginable)
      #   link_conflict    — the account was re-emailed since issuance, OR the
      #                      (provider,issuer,uid) is already bound to a different
      #                      account (defence-in-depth)
      #   link_invalidated — a credential change advanced the account's password
      #                      watermark since the token was issued (criterion 3)
      #   link_error       — the watermark could NOT be read (datastore outage /
      #                      unresolvable Customer). Same 409 and same dead-end as
      #                      link_invalidated, separate code so the copy does not
      #                      tell the user their credentials changed when they did not
      #   confirm_rate_limited — too many confirm attempts from this client (429);
      #                      carries retry_after seconds. Distinct from the
      #                      interstitial's link_rate_limited: this one is about the
      #                      CLIENT, not the link — the copy must say "wait", never
      #                      "the link is dead"
      def handle_sso_link_confirm_routes(r)
        r.on 'sso-link-confirm' do
          # RESTRICT_TO ENFORCEMENT (ADR-024 A1/A7, #4139). Mailbox-proof SSO
          # linking is a continuation of an SSO sign-in and — unlike link-sso —
          # its POST establishes a session on token possession alone, so it is a
          # credential-bearing surface that must go dark with the SSO method on
          # hosts that restrict it away. App-owned Roda route, so the
          # before_rodauth gate does not cover it.
          unless Auth::RestrictTo.allows?(r.env, 'sso')
            response.status = 404
            next Auth::ErrorTranslator::NOT_FOUND_BODY
          end

          # GET /auth/sso-link-confirm/:token — consent display context.
          # Returns ONLY the provider name and claimed email; never the account id,
          # uid, issuer, sid, or watermark. NEVER consumes the token (see the
          # module comment). Missing/consumed/expired token → 404.
          r.get String do |token|
            verification = Onetime::SsoLinkVerification.load(token)
            unless verification
              response.status = 404
              next { error: 'This linking request is no longer valid.', error_code: 'link_expired' }
            end

            response.headers['Content-Type'] = 'application/json'
            verification.to_display
          rescue StandardError => ex
            auth_logger.error 'Error loading SSO link verification', { exception: ex }
            response.status = 500
            { error: 'Failed to load linking request' }
          end

          # POST /auth/sso-link-confirm — consume the token, bind the identity, and
          # establish the login session. Body: { token }.
          r.post do
            # Rodauth's JSON feature parses request bodies only for its OWN routes;
            # this is a custom Roda route, so parse the JSON body here (falling back
            # to form/query params).
            token = json_body_params(request, :token)[:token]

            if token.empty?
              response.status = 400
              next { error: 'A linking token is required.', error_code: 'invalid_request' }
            end

            # RATE LIMIT (#3840 PR #3900 review) — gate BEFORE the op consumes the
            # token, keyed per client (see #sso_link_confirm_throttle_subject).
            # Raises Onetime::LimitExceeded when locked -> 429 (rescued below,
            # ahead of the generic StandardError rescue that would mask it as 500).
            throttle_subject = sso_link_confirm_throttle_subject(request.ip)
            check_login_rate_limit!(throttle_subject) if throttle_subject

            result = Auth::Operations::ConfirmSsoLink.call(
              db: rodauth.db,
              token: token,
              current_sid: sso_link_confirm_current_sid,
              mfa_feature_loaded: rodauth.respond_to?(:otp_auth_route),
              webauthn_feature_loaded: rodauth.respond_to?(:webauthn_auth_route),
            )

            case result.status
            when :link_expired
              # The guessable credential HERE is the token itself, so a token that
              # resolves to nothing IS the failed-guess signal — count it toward the
              # per-client throttle. (The other failure statuses required a REAL
              # token to reach, so they are not guesses and are not recorded.)
              record_failed_login_attempt!(throttle_subject) if throttle_subject
              response.status = 401
              next {
                error: 'This linking request has expired. Please sign in with SSO again.',
                error_code: 'link_expired',
              }
            when :link_conflict
              response.status = 409
              next { error: 'This linking request could not be completed.', error_code: 'link_conflict' }
            when :link_invalidated
              response.status = 409
              next {
                error: 'Your account credentials changed after this link was sent. Please sign in with SSO again.',
                error_code: 'link_invalidated',
              }
            when :link_error
              # The op could not READ the credential watermark (datastore outage),
              # so it fails secure — but nothing about this account changed. 409,
              # NOT a 5xx: the token was already consumed before the probe ran, so
              # this link can never succeed and a status that invites a retry of the
              # SAME link would be a lie. Terminal, like every other failure here.
              response.status = 409
              next {
                error: "We couldn't verify this linking request. Please sign in with SSO again.",
                error_code: 'link_error',
              }
            end

            # Verified credential (the token resolved and every check passed) ->
            # clear the per-client throttle so a legitimate user who burned attempts
            # on stale emailed links is not left one failure from lockout. Mirrors
            # the interstitial's clear-on-verified-credential.
            clear_login_rate_limit!(throttle_subject) if throttle_subject

            # result.status == :ok — the identity is bound (or deferred for MFA).
            # Establish the session through Rodauth's OWN login machinery so
            # after_login runs (Redis session blob via SyncSession — the real app
            # auth gate — plus active_sessions and MFA detection). account_from_login
            # applies the open-status filter, so a closed/absent account yields nil
            # here → link_expired (the op's bind onto such an account is inert).
            unless rodauth.account_from_login(result.email)
              response.status = 401
              next { error: 'This linking request is no longer valid.', error_code: 'link_expired' }
            end

            auth_logger.warn 'SSO identity linked via mailbox proof',
              {
                account_id: result.account_id,
                provider: result.provider,
                bound: result.bound,
                mfa_pending: result.second_factor_pending,
              }

            # login('sso_link_confirm') runs before_login/login_session/after_login
            # and THROWS Rodauth's JSON login response — 200 { success, … } for a
            # non-MFA account, or the SAME mfa_required body POST /auth/login emits
            # when a second factor is pending. The SPA already handles both shapes.
            # The auth_type string is only the authenticated_by label; login does not
            # re-verify a credential (there is none — mailbox proof already authorized
            # this), matching how magic-link establishes a passwordless session.
            #
            # DEFERRED BIND (#3877): when the op deferred the bind for a pending
            # second factor (bound: false), stash the authorized bind tuple so
            # after_two_factor_authentication completes it once the OTP succeeds —
            # otherwise an MFA passwordless account would re-hit this flow forever,
            # never linked. Mirrors the interstitial (Auth::Routes::LinkSso): the
            # login block is the ONLY point that sees the login's FINAL sid
            # (login_session re-keys the session; a stash keyed to the old sid would
            # never be found) and precedes after_login. Best-effort by contract — a
            # failed stash is logged inside `.defer` and the login proceeds unlinked.
            rodauth.login('sso_link_confirm') do
              if result.second_factor_pending
                Auth::Operations::DeferredSsoBind.defer(
                  sid: session.id&.public_id,
                  account_id: result.account_id,
                  provider: result.provider,
                  issuer: result.issuer,
                  uid: result.uid,
                )
              end
            end
          rescue Onetime::LimitExceeded => ex
            # Must precede the generic StandardError rescue below (which would turn
            # this into a 500). Same ADR-013-style 429 shape as the interstitial's
            # link_rate_limited, under its own code: this failure is about the
            # CLIENT, not the link, so the SPA copy says "wait", not "link is dead".
            auth_logger.warn 'SSO link confirm rate limited', { retry_after: ex.retry_after }
            response.status                 = 429
            response.headers['Retry-After'] = ex.retry_after.to_s if ex.retry_after
            {
              error: 'Too many attempts. Please try again later.',
              error_code: 'confirm_rate_limited',
              retry_after: ex.retry_after,
            }
          rescue StandardError => ex
            auth_logger.error 'Error completing SSO link confirmation', { exception: ex }
            response.status = 500
            { error: 'Failed to complete linking' }
          end
        end
      end

      private

      # Current request's session id, for the op's SOFT cross-device check. Best
      # effort: mailbox proof is inherently cross-device, so a nil here just means
      # the soft check is skipped — never a failure.
      def sso_link_confirm_current_sid
        rodauth.session.id&.public_id
      rescue StandardError => ex
        # Surface the swallowed error rather than resolving to nil in silence. We
        # still fall through to nil (fail SOFT: the cross-device check is advisory
        # and is simply skipped), but the sid feeds ONLY that check — and
        # ConfirmSsoLink#warn_on_cross_device early-returns on an empty sid — so a
        # SYSTEMIC session.id failure would stop the cross-device audit event
        # emitting permanently and undetectably.
        #
        # SAME event name as the identical resolver in config/hooks/account.rb
        # (after_change_password) so one audit query covers both sites.
        Auth::Logging.log_auth_event(
          :current_session_id_unresolved,
          level: :warn,
          route: :sso_link_confirm,
          error: ex.message,
        )
        nil
      end

      # Throttle subject for the confirm POST, or nil when no client IP resolved.
      #
      # WHY PER-CLIENT-IP, NOT PER-EMAIL: on the interstitial (link_sso) the
      # guessable credential is the account PASSWORD, and the challenge — loaded
      # before the check — supplies the email subject. Here the guessable
      # credential IS the token (mailbox proof): a guessed token resolves to no
      # record, so there is no email to key on at exactly the moment throttling
      # matters. The only stable identifier a guess carries is the client IP —
      # request.ip here is the privacy-MASKED address (Otto's IPPrivacyMiddleware
      # rewrites REMOTE_ADDR upstream), the same value the interstitial's
      # email+IP tier keys on, so the throttle granularity matches.
      #
      # The IP is embedded in the SUBJECT with a nil ip argument — the limiter's
      # documented "global tier only" path — giving one per-client key pair
      # (login:attempts:sso-link-confirm:{ip}) capped at GLOBAL_MAX_ATTEMPTS per
      # window. Passing a FIXED subject with the ip argument instead would also
      # create a single global bucket shared by ALL clients: GLOBAL_MAX_ATTEMPTS
      # bogus POSTs from anyone would lock every user's mailbox confirm for
      # LOCKOUT_DURATION — a trivial DoS. Per-client keys cannot be poisoned
      # across users. An EMPTY IP skips the throttle (nil) for the same reason:
      # a shared fallback bucket would reopen that DoS. The token is 256-bit
      # (SecureRandom.urlsafe_base64(32)), so this limiter is defence-in-depth
      # bounding probe volume, not the primary guard against guessing.
      def sso_link_confirm_throttle_subject(client_ip)
        ip = client_ip.to_s
        return nil if ip.empty?

        "sso-link-confirm:#{ip}"
      end
    end
  end
end
