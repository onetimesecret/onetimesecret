# apps/web/auth/routes/sso_link_confirm.rb
#
# frozen_string_literal: true

require 'auth/operations/confirm_sso_link'

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
      # Error codes returned to the SPA (SsoLinkConfirm.vue maps these to copy):
      #   invalid_request  — token missing from the POST body
      #   link_expired     — token missing / already consumed / expired, or the
      #                      snapshotted account vanished (or is no longer loginable)
      #   link_conflict    — the account was re-emailed since issuance, OR the
      #                      (provider,issuer,uid) is already bound to a different
      #                      account (defence-in-depth)
      #   link_invalidated — a credential change advanced the account's password
      #                      watermark since the token was issued (criterion 3)
      def handle_sso_link_confirm_routes(r)
        r.on 'sso-link-confirm' do
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
            token = sso_link_confirm_params(request)[:token]

            if token.empty?
              response.status = 400
              next { error: 'A linking token is required.', error_code: 'invalid_request' }
            end

            result = Auth::Operations::ConfirmSsoLink.call(
              db: rodauth.db,
              token: token,
              current_sid: sso_link_confirm_current_sid,
              mfa_feature_loaded: rodauth.respond_to?(:otp_auth_route),
            )

            case result.status
            when :link_expired
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
            end

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
            rodauth.login('sso_link_confirm')
          rescue StandardError => ex
            auth_logger.error 'Error completing SSO link confirmation', { exception: ex }
            response.status = 500
            { error: 'Failed to complete linking' }
          end
        end
      end

      private

      # Extract { token } from a JSON body (Content-Type application/json), falling
      # back to form/query params. Returns a string value ('' when absent). Rewinds
      # the input so nothing downstream is surprised by a consumed body.
      def sso_link_confirm_params(request)
        raw = request.body&.read.to_s
        request.body.rewind if request.body.respond_to?(:rewind)

        parsed = begin
          raw.empty? ? {} : JSON.parse(raw)
        rescue JSON::ParserError
          {}
        end
        parsed = {} unless parsed.is_a?(Hash)

        { token: (parsed['token'] || request.params['token']).to_s }
      end

      # Current request's session id, for the op's SOFT cross-device check. Best
      # effort: mailbox proof is inherently cross-device, so a nil here just means
      # the soft check is skipped — never a failure.
      def sso_link_confirm_current_sid
        rodauth.session.id&.public_id
      rescue StandardError
        nil
      end
    end
  end
end
