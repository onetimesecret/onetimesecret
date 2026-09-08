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

require_relative 'config'
require_relative 'error_translator'
require_relative 'routes/account'
require_relative 'routes/active_sessions'
require_relative 'routes/identities'
require_relative 'routes/webauthn_credentials'
require_relative 'routes/link_sso'
require_relative 'routes/sso_link_confirm'
require_relative 'routes/mfa'
require_relative 'routes/admin'
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
    include Auth::Routes::LinkSso
    include Auth::Routes::SsoLinkConfirm
    include Auth::Routes::Admin

    plugin :json, parser: true  # Parse incoming JSON request bodies
    plugin :halt
    plugin :status_handler
    plugin :flash  # Required for Rodauth flash messages on browser redirects (e.g., OmniAuth)

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
    # Logging: 500s log at :error with backtrace so production failures are
    # not silent (Roda's :error_handler does not log by default). Translated
    # typed exceptions log at the per-class level from
    # Auth::ErrorTranslator::LOG_LEVEL_BY_CLASS, which mirrors the
    # `log_level:` values passed to `register_error_handler` in
    # `lib/onetime/application/otto_hooks.rb`. That keeps the Roda Auth app
    # and Otto apps emitting at the same level for the same exception class.
    plugin :error_handler do |e|
      status, body             = Auth::ErrorTranslator.translate(e)
      body                     = Onetime::Application::ErrorCorrelation.apply(body, request.env, e)
      if status >= 500
        auth_logger.error 'Auth router unhandled exception', exception: e
      else
        level = Auth::ErrorTranslator.level_for(e)
        auth_logger.public_send(
          level,
          'Auth router translated exception',
          exception_class: e.class.name,
          status: status,
        )
      end
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

      # Full-mode active-session enforcement for the /auth surface
      # (Onetime::ActiveSessionGate, terms defined there). The routes below,
      # Rodauth's own included, authenticate on `rodauth.logged_in?`, which
      # reads only the Rack session; without this check a Rack session whose
      # active-session row had been revoked could still read the account,
      # unlink identities, remove passkeys and revoke every OTHER row while
      # being refused everywhere else. Ahead of r.rodauth so that Rodauth's
      # login-required routes (change-password, webauthn-remove, ...) are
      # covered too. Anonymous requests are :skipped at no cost.
      case Onetime::ActiveSessionGate.verdict(session, env: env)
      when :revoked
        # Destroy, then refuse: the same handling this surface already gives
        # an orphaned session (Auth::Routes::Account#require_valid_account,
        # the around_rodauth rescue in config/overrides/error_handling.rb)
        # and what Rodauth's own check_active_session does. Clearing the Rack
        # session turns the request anonymous; the memo goes with it, since
        # the identity it was reached for is gone. Two routes are then
        # answered differently from the rest. Login continues, so that a
        # stale cookie can sign in again without first bouncing off its own
        # revoked session. Logout is answered here with success, as the
        # orphan rescue does: the Rack session is already destroyed, which
        # is all the user asked for, and Rodauth's logout must not run on
        # it (its global-logout branch dereferences the account, and a
        # revoked browser must not be able to revoke anyone else's rows
        # through it anyway). Everything else answers 401 with the
        # session_expired key the SPA already translates.
        Auth::Logging.log_auth_event(
          :active_session_revoked,
          level: :info,
          path: r.path_info,
          account_id: session['account_id'],
        )
        rodauth.clear_session
        env.delete(Onetime::ActiveSessionGate::ENV_KEY)

        case r.path_info
        when "/#{rodauth.login_route}"
          nil
        when "/#{rodauth.logout_route}"
          next { success: true, message: 'web.auth.logout.success' }
        else
          response.status = 401
          next { error: 'web.auth.security.session_expired', success: false }
        end
      when :unavailable
        # Fail closed, but keep the Rack session: it is honoured again once
        # the authdb answers. Same posture and status as the Otto strategies'
        # [SESSION_UNVERIFIED] refusal. Logout is the one exception: signing
        # out grants nothing, so the Rack session is destroyed and the logout
        # answered here (Rodauth's would need the same unreachable authdb);
        # its active-session row waits for the sweep.
        if r.path_info == "/#{rodauth.logout_route}"
          rodauth.clear_session
          env.delete(Onetime::ActiveSessionGate::ENV_KEY)
          next { success: true, message: 'web.auth.logout.success' }
        end

        response.status = 401
        next { error: 'Session could not be verified; try again', error_type: 'SessionUnverified' }
      end

      # All Rodauth routes (login, logout, create-account, reset-password, etc.)
      # Rodauth handles all /auth/* routes when full mode is enabled
      r.rodauth

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

      # SSO sign-in interstitial: password-challenge linking (#3840 Phase 3)
      handle_link_sso_routes(r)

      # SSO mailbox-proof linking for passwordless accounts (#3840 Phase 4)
      handle_sso_link_confirm_routes(r)

      handle_admin_routes(r)

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
