# apps/web/auth/router.rb
#
# frozen_string_literal: true

require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

require 'onetime/logger_methods'
require 'onetime/application/error_correlation'
require 'onetime/models/custom_domain/signin_config'
require 'onetime/session/customer_session_evaluator'
require 'onetime/session/failure_code'
require 'onetime/sso_provider/flow_session_keys'

require_relative 'config'
require_relative 'error_translator'
require_relative 'session_recheck'
require_relative 'routes/account'
require_relative 'routes/active_sessions'
require_relative 'routes/identities'
require_relative 'routes/webauthn_credentials'
require_relative 'routes/reauth'
require_relative 'routes/link_sso'
require_relative 'routes/sso_link_confirm'
require_relative 'routes/mfa'
require_relative 'routes/health'

module Auth
  # This is the Roda application, which handles all routing for the auth service.
  class Router < Roda
    include Onetime::LoggerMethods

    # IP privacy is mounted once in the universal MiddlewareStack
    # (lib/onetime/application/middleware_stack.rb), which resolves the
    # canonical env['otto.client_ip'] before this Roda app runs. No per-router
    # IPPrivacyMiddleware mount here — it would be a no-op behind otto's
    # idempotency guard.

    # Include session validation helpers
    # TODO: Implement these modules
    # include Auth::Helpers::SessionValidation
    #
    # Include route modules
    # include Auth::Routes::Validation
    include Auth::Routes::Health
    include Auth::Routes::Account
    include Auth::Routes::MFA
    include Auth::Routes::ActiveSessions
    include Auth::Routes::Identities
    include Auth::Routes::WebauthnCredentials
    include Auth::Routes::Reauth
    include Auth::Routes::LinkSso
    include Auth::Routes::SsoLinkConfirm

    plugin :json, parser: true  # Parse incoming JSON request bodies
    plugin :halt
    plugin :status_handler
    plugin :flash  # Required for Rodauth flash messages on browser redirects (e.g., OmniAuth)

    # Everything this app answers is authentication state: login and MFA
    # results, the account, its sessions and credentials, and the refusals in
    # between. None of it may be stored by a browser or an intermediary
    # (#4461; OWASP ASVS 5.0 14.3.2). It is a default, applied with `||=` when
    # the response is finished, so a route that sets its own Cache-Control
    # (routes/reauth.rb) keeps it. Roda merges this into its existing default
    # headers; Content-Type is unaffected.
    plugin :default_headers, 'cache-control' => 'private, no-store'

    # plugin :sessions,
    #   key: 'onetime.session',
    #   secret: ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))

    # All Rodauth configuration is now in apps/web/auth/config.rb
    # Use its Config class for all authentication configuration.
    plugin :rodauth, auth_class: Auth::Config

    # Translate typed Onetime exceptions to ADR-013 wire shape
    # ({ error, error_type, ...class-specific }) when they propagate out of a
    # route block. Additive: existing per-route `rescue StandardError` blocks
    # still intercept first, so this handler only fires for exceptions that
    # escape them — typically typed exceptions raised from routes that have
    # been converted to the typed-raise pattern.
    #
    # Rodauth's own auth-flow errors are caught inside Rodauth before
    # propagating here and are unaffected.
    #
    # The body is JSON-serialized in-line rather than relying on `plugin :json`
    # auto-wrapping the :error_handler return value; that interaction depends
    # on plugin load order and is brittle. Serializing here keeps the wire
    # shape correct regardless of plugin layering.
    #
    # Correlation: the translated body is run through the shared
    # Onetime::Application::ErrorCorrelation helper — the same one the Otto
    # hooks use — which echoes the request's x-request-id into the JSON body and
    # stashes the error_type into the Rack env, so a typed /auth error and its
    # RequestLogger line share one greppable id (see #3520). request.env is the
    # same hash RequestLogger reads one frame up the MiddlewareStack, so the
    # stash lands on the request-log line that already carries request_id (no
    # logger change needed; added in #3518). The router-level 404 fallbacks
    # (status_handler/catch-all) are returned from routing, not raised, so they
    # bypass this handler and stay request-independent — the x-request-id
    # response header still correlates them.
    #
    # Logging: Auth::ErrorTranslator.log_entry decides level and message.
    # An exception the translator does not know logs at :error as "unhandled
    # exception" with backtrace so production failures are not silent (Roda's
    # :error_handler does not log by default). A translated exception logs at
    # the per-class level from Auth::ErrorTranslator::LOG_LEVEL_BY_CLASS,
    # which mirrors the `log_level:` values passed to `register_error_handler`
    # in `lib/onetime/application/otto_hooks.rb`. That keeps the Roda Auth app
    # and Otto apps emitting at the same level for the same exception class.
    # The split is on "translated", not on the status: the retryable 503s
    # (AuthDatabaseBusy, AccountProvisioningUnavailable) are deliberate
    # answers at :warn, not unhandled exceptions.
    plugin :error_handler do |e|
      status, body             = Auth::ErrorTranslator.translate(e)
      body                     = Onetime::Application::ErrorCorrelation.apply(body, request.env, e)
      level, message, payload  = Auth::ErrorTranslator.log_entry(e)
      auth_logger.public_send(level, message, payload)
      response.status          = status
      response['content-type'] = 'application/json'
      body.to_json
    end

    # Both router-level 404 paths (status_handler and the route-block
    # catch-all below) return Auth::ErrorTranslator::NOT_FOUND_BODY so they
    # cannot drift apart. The spec at
    # apps/web/auth/spec/integration/router_error_shape_spec.rb pins the shape.
    status_handler(404) do
      Auth::ErrorTranslator::NOT_FOUND_BODY
    end

    # Rodauth routes that need no login: the ones a browser reaches to
    # present a credential (password, passkey, magic link, SSO) or to start
    # or finish an account-lifecycle flow (sign-up, verification, password
    # reset, unlock). Rodauth marks none of its routes as login-required in
    # any introspectable way; the login-required ones call require_login /
    # require_account in their before_*_route hooks, so this list is kept by
    # hand. Route names, not paths: each is read off the Rodauth instance so
    # a renamed route follows, and one whose feature is not enabled has no
    # `<name>_route` reader and is skipped. The OmniAuth routes are matched
    # on their prefix because their provider segment is per-install (and,
    # for tenant SSO, per-request).
    ANONYMOUS_RODAUTH_ROUTES = [
      :login,
      :webauthn_login,
      :webauthn_autofill_js,
      :email_auth,
      :email_auth_request,
      :create_account,
      :verify_account,
      :verify_account_resend,
      :reset_password,
      :reset_password_request,
      :unlock_account,
      :unlock_account_request,
    ].freeze

    MFA_PENDING_RODAUTH_ROUTES = [
      :otp_auth,
      :recovery_auth,
      :webauthn_auth,
    ].freeze

    def named_rodauth_route?(path, names)
      names.any? do |name|
        reader = :"#{name}_route"
        rodauth.respond_to?(reader) && path == "/#{rodauth.public_send(reader)}"
      end
    end

    # Whether `path` (request.path_info, relative to the /auth mount) is one
    # Rodauth serves without a login. Read by the active-session gate's
    # :revoked branch in the route block below.
    def anonymous_rodauth_route?(path)
      return true if named_rodauth_route?(path, ANONYMOUS_RODAUTH_ROUTES)

      rodauth.respond_to?(:omniauth_prefix) && path.start_with?("#{rodauth.omniauth_prefix}/")
    end

    # Routes this router serves itself (not Rodauth's) that the MFA challenge
    # page cannot work without, keyed by request method; exact matches on
    # request.path_info. Deliberately tiny and hand-kept:
    #
    #   GET /mfa-status   The challenge page (MfaChallenge.vue, via useMfa's
    #                     fetchMfaStatus) reads the per-factor booleans on
    #                     mount to decide which factors to offer. Refused, the
    #                     passkey affordance never renders, a TOTP user sees
    #                     an error banner, and the page loses its recovery
    #                     from a session marked awaiting_mfa for an account
    #                     with no second factor. The body carries factor
    #                     booleans, a recovery-code count and the OTP
    #                     last-use time; no identifiers.
    #
    # Everything else the page calls is either a Rodauth route already in
    # MFA_PENDING_RODAUTH_ROUTES (the passkey challenge fetch and its
    # verification are both POST /webauthn-auth), logout, or lives outside
    # the /auth mount (/bootstrap/me). /account and /account.json are NOT
    # here: they return the account's id and email, which a session that has
    # presented only one factor must not read.
    MFA_PENDING_CUSTOM_ROUTES = {
      'GET' => ['/mfa-status'].freeze,
    }.freeze

    # A partial two-factor session may only reach the routes that finish or
    # abandon the challenge: the second-factor completion routes
    # (MFA_PENDING_RODAUTH_ROUTES), logout, and the method-scoped custom
    # routes the challenge page depends on (MFA_PENDING_CUSTOM_ROUTES).
    # Anonymous credential and recovery routes are NOT permitted here —
    # allowing them lets a partial MFA session start unrelated
    # account-lifecycle flows (create-account, verify-account,
    # reset-password-request, OmniAuth) while the challenge sits half-finished.
    def mfa_pending_route?(request_method, path)
      return true if path == "/#{rodauth.logout_route}"
      return true if named_rodauth_route?(path, MFA_PENDING_RODAUTH_ROUTES)

      MFA_PENDING_CUSTOM_ROUTES.fetch(request_method, []).include?(path)
    end

    # How the gate's :revoked branch answers `path`: the logout is answered
    # here, a route Rodauth serves without a login continues as anonymous,
    # everything else is refused.
    def revoked_outcome(path)
      return :logout_answered if path == "/#{rodauth.logout_route}"
      return :continued_anonymous if anonymous_rodauth_route?(path)

      :refused
    end

    # The Rack-session keys a strategy parks during the request phase of an
    # SSO flow and consumes in the callback (omniauth-oauth2,
    # omniauth_openid_connect, RequestBoundSAML). Clearing the Rack session
    # between the two phases drops them, and the callback then fails state /
    # InResponseTo verification. One list, shared with the tenant hook that
    # deletes them on supersession: Onetime::SsoProvider::FlowSessionKeys.
    OMNIAUTH_FLOW_KEYS = Onetime::SsoProvider::FlowSessionKeys::ALL

    # What the current Rack session is carrying mid-flow, for the gate's
    # log lines: the OmniAuth keys above (in the session blob, dropped by
    # clear_session) and the sidecar hand-off fields bound to its sid
    # holding a live truthy value (sso_connect_intent, link_sso_pending_bind,
    # awaiting_mfa), which #clear_gated_session purges. Both lists empty is
    # the common case. Read-only and best effort: a sidecar probe failure
    # reads as nothing in flight rather than disturbing the refusal.
    def inflight_session_state
      omniauth_keys  = OMNIAUTH_FLOW_KEYS.reject { |key| session[key].nil? }
      sidecar_fields = begin
        Onetime::SessionSidecar.inflight_fields(session.id&.public_id)
      rescue StandardError
        []
      end
      { omniauth_keys: omniauth_keys, sidecar_fields: sidecar_fields }
    end

    # Sign the gated request out: destroy the session and drop both layers of
    # per-request customer-session memoization.
    #
    # This codebase overrides Rodauth's clear_session to `session.destroy`
    # (see Auth::Config::Base), so rodauth.clear_session routes through the
    # store's delete path (Onetime::Session#delete_session). That path
    # already DELs the session blob, purges the sid's sidecar registry keys
    # (SessionSidecar.purge — including the explicit-use hand-off stashes
    # sso_connect_intent / link_sso_pending_bind), and runs the in-flight
    # tripwire that warns if a session is destroyed while a hand-off field
    # still holds a live value. A purge failure there is logged and the
    # sign-out stands, orphans being TTL-bounded. No separate purge is
    # needed here — the destroy leaves nothing behind.
    def clear_gated_session
      rodauth.clear_session
      Onetime::CustomerSessionEvaluator.forget(env)
      Onetime::ActiveSessionGate.forget(env)
    end

    # A session refusal body plus its stable `code` / `code_scope` (#4462).
    # The existing fields are the caller's and are not changed; the codes are
    # the same ones the Otto surfaces answer with
    # (Onetime::Middleware::SessionFailureCode), so a client reads one
    # vocabulary on every surface. `reason` is the one this router acted on,
    # which may be Auth::SessionRecheck's rather than the evaluator's. Logged
    # here, once per refusal, with the same code and the request id (#4461).
    def session_refusal(body, reason)
      Onetime::SessionFailureCode.log_refusal(reason, env)
      body.merge(Onetime::SessionFailureCode.for(reason).transform_keys(&:to_sym))
    end

    # Main routing logic
    route do |r|
      # Debug logging for development
      Onetime.development? do
        http_logger.debug 'Auth router request',
          {
            method: r.request_method,
            path_info: r.path_info,
            request_uri: r.env['REQUEST_URI'],
            script_name: r.env['SCRIPT_NAME'],
          }
      end

      # Master kill-switch (#3911): when AUTH_ENABLED is false the whole
      # /auth surface goes dark before r.rodauth can process credentials or
      # mint a session. Only the health endpoint stays reachable — it is a
      # monitored path (lib/onetime/middleware/health_access_control.rb).
      # Every other /auth/* path 404s with the shared ADR-013 body.
      unless Onetime::CustomDomain::SigninConfig.global_auth_enabled
        handle_health_routes(r)

        Auth::Logging.log_auth_event(
          :auth_surface_disabled,
          level: :debug,
          path: r.path_info,
        )

        response.status = 404
        next Auth::ErrorTranslator::NOT_FOUND_BODY
      end

      # Root path - Auth app info
      # When mounted at /auth, this handles requests to /auth and /auth/
      #
      # No version field: this path is anonymous-reachable (it sits ahead of
      # r.rodauth), and the build version fingerprints the install for CVE
      # matching. Callers that need it and are entitled to it use
      # GET /api/v3/version, which is auth-gated. The version is still
      # reported by the /auth/health endpoint, which HealthAccessControl
      # restricts to loopback/RFC1918.
      r.is do
        r.get do
          { message: 'OneTimeSecret Authentication Service' }
        end
      end

      # Rodauth authenticates these routes from the Rack session alone:
      # `rodauth.logged_in?` is `session['account_id']` being present, with no
      # reference to the app-level `authenticated` flag. Obtain the shared
      # customer-session verdict before r.rodauth, then let
      # Auth::SessionRecheck fill in what the evaluator had not reached when
      # it answered. This does not reorder the shared evaluator.
      #
      # The re-check is keyed on Rodauth's notion of logged in, not on
      # `session['authenticated'] == true`, because that flag is exactly what
      # the two affected kinds of session lack:
      #
      #   :awaiting_mfa       An MFA-pending session. The evaluator answers
      #                       before its surface and active-session checks, so
      #                       both run here: a session revoked or replayed on
      #                       another surface mid-challenge must not be able
      #                       to complete otp-auth / webauthn-auth /
      #                       recovery-auth.
      #   :not_authenticated  With an account_id, an autologin session
      #                       (verify-account, invite create-account)
      #                       that never went through after_login. Rodauth
      #                       serves it every login-required route, so both
      #                       checks run here too. Without an account_id the
      #                       request is genuinely anonymous and neither check
      #                       applies.
      #   :customer_unavailable  The customer store, or the request's
      #                       surface, could not be read; only the
      #                       active-session row is left to examine.
      #                       Revocation is destructive on this surface and
      #                       must not be hidden by a datastore outage.
      #
      # Invariant: every other rejection is definitive and is never
      # overwritten by a fallback :active_session_unavailable, which would
      # preserve the cookie.
      customer_session_verdict = Onetime::CustomerSessionEvaluator.evaluate(session, env: env)
      auth_session_reason      = Auth::SessionRecheck.reason_for(customer_session_verdict, session, env)

      case auth_session_reason
      when :authenticated
        # Continue to authenticated routes below.
      when :awaiting_mfa
        # Surface matched and the active-session row is live (or the session
        # predates the join key); see Auth::SessionRecheck.
        unless mfa_pending_route?(r.request_method, r.path_info)
          response.status = 401
          next session_refusal({ error: 'Authentication required' }, auth_session_reason)
        end
      when :active_session_revoked, :surface_mismatch
        outcome = revoked_outcome(r.path_info)

        case auth_session_reason
        when :active_session_revoked
          # Destroy, then refuse: the same handling this surface already gives
          # an orphaned session (Auth::Routes::Account#require_valid_account,
          # the around_rodauth rescue in config/overrides/error_handling.rb)
          # and what Rodauth's own check_active_session does. Clearing the Rack
          # session turns the request anonymous; the memo goes with it, since
          # the identity it was reached for is gone. Two kinds of route are
          # then answered differently from the rest. The routes Rodauth serves
          # without a login (#anonymous_rodauth_route?) continue as the
          # anonymous request they now are, so that a stale cookie can present
          # a credential without first bouncing off its own revoked session:
          # a 401 there would self-heal on retry, but an OmniAuth callback has
          # no retry, its authorization code being spent on the first attempt.
          # Logout is answered here with success, as the orphan rescue does:
          # the Rack session is already destroyed, which is all the user asked
          # for, and Rodauth's logout must not run on it (its global-logout
          # branch dereferences the account, and a revoked browser must not be
          # able to revoke anyone else's rows through it anyway). Everything
          # else answers 401 with the session_expired key the SPA already
          # translates.
          #
          # Logged before the clear, with the outcome and whatever the Rack
          # session was carrying mid-flow. The one case the exemption cannot
          # save gets its own warn line: a row revoked between an SSO flow's
          # request phase and its callback. The callback is exempt and runs,
          # but the clear has dropped the OmniAuth state the callback verifies
          # against, so it fails and the provider's one-time authorization code
          # is spent. The user is signed out, which is what the revocation
          # asked for, and restarts the flow after signing in. Support sees an
          # SSO failure at the same moment as a revocation; this line is what
          # ties the two together. The sidecar hand-off fields are purged with
          # the clear (#clear_gated_session); they are named here first so the
          # stranded hand-off is not silent, the same warning the store's own
          # tripwire gives a logout.
          inflight = inflight_session_state
          Auth::Logging.log_auth_event(
            :active_session_revoked,
            level: :info,
            path: r.path_info,
            account_id: session['account_id'],
            outcome: outcome,
            **inflight,
          )
          if inflight.values.any?(&:any?)
            Auth::Logging.log_auth_event(
              :active_session_revoked_mid_flow,
              level: :warn,
              path: r.path_info,
              account_id: session['account_id'],
              outcome: outcome,
              **inflight,
              consequence: 'OmniAuth keys are dropped with the Rack session, so an in-flight SSO callback ' \
                           'fails state verification and its authorization code is spent; sidecar hand-off ' \
                           'fields are purged with the session. The user signs in again and restarts the flow.',
            )
          end
        when :surface_mismatch
          Auth::Logging.log_auth_event(
            :session_surface_mismatch,
            level: :warn,
            path: r.path_info,
            account_id: session['account_id'],
            recorded_surface: Onetime::SessionSurface.recorded(session),
            request_surface: Onetime::SessionSurface.for_env(env),
            outcome: outcome,
          )
        end

        clear_gated_session

        case outcome
        when :logout_answered
          next { success: true, message: 'web.auth.logout.success' }
        when :refused
          response.status = 401
          next session_refusal({ error: 'web.auth.security.session_expired', success: false }, auth_session_reason)
        end
      when :active_session_unavailable, :customer_unavailable
        # Fail closed, but keep the Rack session so a transient verification
        # failure can recover. Logout is the one exception: signing out grants
        # nothing, so destroy the Rack session and answer it here.
        logout = r.path_info == "/#{rodauth.logout_route}"
        Auth::Logging.log_auth_event(
          auth_session_reason == :active_session_unavailable ? :active_session_unverified : :customer_session_unverified,
          level: :warn,
          path: r.path_info,
          account_id: session['account_id'],
          outcome: logout ? :logout_answered : :refused,
        )
        if logout
          clear_gated_session
          next { success: true, message: 'web.auth.logout.success' }
        end

        response.status = 401
        next session_refusal(
          { error: 'Session could not be verified; try again', error_type: 'SessionUnverified' },
          auth_session_reason,
        )
      when :session_missing, :not_authenticated
        # Nothing to destroy, by construction. The evaluator answers
        # :not_authenticated only when the `authenticated` flag is absent, so
        # this is one of two requests:
        #
        #   - Genuinely anonymous (no account_id). Rodauth treats it as logged
        #     out; its anonymous routes run and its login-required routes
        #     refuse it.
        #   - A Rodauth login without the app-level flag: an autologin session
        #     (verify-account, invite create-account). It reaches
        #     this branch only after Auth::SessionRecheck matched its surface
        #     and found its active-session row live (or found no join key to
        #     check, the gate's existing exemption); a mismatch or a revoked
        #     row was turned into :surface_mismatch / :active_session_revoked
        #     above and destroyed there. What is left is a valid Rodauth
        #     login, and destroying it would sign the user out on the request
        #     after they verified their account or reset their password.
        #
        # Continue to Rodauth, which authorizes it as it would any login.
      when :identity_missing, :customer_not_found, :account_suspended, :stale_credentials,
           :admin_session_expired
        # A definitive rejection destroys the invalid session before dispatch.
        # Anonymous credential/recovery routes may continue, logout succeeds,
        # and login-required routes retain the established session-expired
        # refusal. The evaluator reaches each of these reasons only past its
        # `authenticated == true` check, so the flag is set whenever this
        # branch runs on the evaluator's own verdict. The guard also accepts
        # Rodauth's notion of logged in, so that the destroy never depends on
        # the app-level flag alone: what matters on this surface is whether
        # Rodauth would authorize the session, and a session Rodauth would
        # authorize must not survive a definitive rejection. A Rack session
        # that is neither has nothing to destroy and falls through.
        #
        # Logged before the clear, like the :revoked branch, with whatever the
        # Rack session was carrying mid-flow. An SSO callback that arrives on
        # such a session is handled as it is there: the session is destroyed,
        # the callback continues as the anonymous request it now is, and any
        # Connect intent is purged with the session, so nothing can be bound
        # to the rejected account. The hook-level Connect refusal
        # (hooks/omniauth_connect.rb) is not reached from a rejected session;
        # this line is the record of why that Connect went nowhere.
        if session['authenticated'] == true || rodauth.logged_in?
          outcome = revoked_outcome(r.path_info)
          Auth::Logging.log_auth_event(
            :customer_session_rejected,
            level: :warn,
            path: r.path_info,
            account_id: session['account_id'],
            reason: auth_session_reason,
            outcome: outcome,
            **inflight_session_state,
          )
          clear_gated_session

          case outcome
          when :logout_answered
            next { success: true, message: 'web.auth.logout.success' }
          when :refused
            response.status = 401
            next session_refusal({ error: 'web.auth.security.session_expired', success: false }, auth_session_reason)
          end
        end
      else
        raise "Unhandled customer-session reason: #{auth_session_reason.inspect}"
      end

      # All Rodauth routes (login, logout, create-account, reset-password, etc.)
      # Rodauth handles all /auth/* routes when full mode is enabled.
      #
      # Rodauth's login/2FA/verify hooks mutate session['authenticated'] and
      # session['awaiting_mfa'] in-band, and it uses `throw :halt` when it
      # answers a route. That halts before any post-r.rodauth invalidation runs,
      # so the CustomerSessionEvaluator memo (populated at the top of this
      # route block) would go stale for anyone else reading env[ENV_KEY] later.
      # An `ensure` block is the only reliable invalidation point for both the
      # halt and pass-through paths. Delete on a hash — cheap and always safe.
      begin
        r.rodauth
      ensure
        # Both memos: the active-session sub-verdict was computed for the same
        # pre-Rodauth identity (a login mints a new join key, a logout removes
        # the row), and Auth::SessionRecheck reads it on its own.
        Onetime::CustomerSessionEvaluator.forget(env)
        Onetime::ActiveSessionGate.forget(env)
      end

      # Account routes (mfa-status, account info)
      handle_account_routes(r)

      # MFA routes (placeholder - uncomment when implemented)
      # handle_mfa_routes(r)

      # Active sessions routes
      handle_active_sessions_routes(r)

      # Linked SSO identities management routes (#3840 Phase 2)
      handle_identities_routes(r)

      # WebAuthn credential (passkey) listing routes; removal stays with
      # Rodauth's POST /auth/webauthn-remove
      handle_webauthn_credentials_routes(r)

      # Surface-aware re-authentication offer and completion endpoints (#4414).
      handle_reauth_routes(r)

      # SSO sign-in interstitial: password-challenge linking (#3840 Phase 3)
      handle_link_sso_routes(r)

      # SSO mailbox-proof linking for passwordless accounts (#3840 Phase 4)
      handle_sso_link_confirm_routes(r)

      handle_health_routes(r)

      # Catch-all for undefined routes (ADR-013 shape; shared with status_handler(404))
      response.status = 404
      Auth::ErrorTranslator::NOT_FOUND_BODY
    end

    # # Returns the current customer from session or nil (anonymous)
    # # @return [Onetime::Customer, nil]
    # def current_customer
    #   return nil unless session['external_id']
    #   Onetime::Customer.find_by_extid(session['external_id'])
    # rescue StandardError => ex
    #   auth_logger.error 'Failed to load customer from session', exception: ex
    #   nil
    # end

    # # Returns the current locale for i18n
    # # @return [String]
    # def current_locale
    #   session['locale'] || 'en'
    # end
  end
end
