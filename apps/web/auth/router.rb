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

require_relative 'config'
require_relative 'error_translator'
require_relative 'routes/account'
require_relative 'routes/active_sessions'
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

      # OAuth/OIDC discovery routes (not auto-mounted by rodauth-oauth).
      # Must be invoked from the routing block; the helpers register their
      # own `request.on('.well-known/...')` matchers internally.
      #
      # JWKS at /jwks is auto-mounted by :oauth_jwt_jwks (pulled in by :oidc)
      # — do not mount it here.
      #
      # See: apps/web/auth/config/features/oauth.rb
      # See: rodauth-oauth-1.6.4/lib/rodauth/features/oidc.rb:188
      # See: rodauth-oauth-1.6.4/lib/rodauth/features/oauth_base.rb:150
      if Onetime.auth_config.oauth_enabled?
        rodauth.load_openid_configuration_route
        # Called without an issuer arg: the optional positional is a path
        # suffix appended to base_url (oauth_base.rb:746–748), not a full
        # issuer URI. Passing rodauth.oauth_jwt_issuer fails because that
        # method is private at the routing-instance level.
        rodauth.load_oauth_server_metadata_route
      end

      # Root path - Auth app info
      # When mounted at /auth, this handles requests to /auth and /auth/
      r.is do
        r.get do
          { message: 'OneTimeSecret Authentication Service', version: Onetime::VERSION }
        end
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
