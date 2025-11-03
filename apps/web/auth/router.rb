# apps/web/auth/router.rb

require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

require 'onetime/logging'

require_relative 'config'
require_relative 'routes/account'
require_relative 'routes/active_sessions'
require_relative 'routes/mfa'
require_relative 'routes/admin'
require_relative 'routes/health'

module Auth
  # This is the Roda application, which handles all routing for the auth service.
  class Router < Roda
    include Onetime::Logging

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

    # plugin :sessions,
    #   key: 'onetime.session',
    #   secret: ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))

    # All Rodauth configuration is now in apps/web/auth/config.rb
    # Use its Config class for all authentication configuration.
    plugin :rodauth, auth_class: Auth::Config

    # Status handlers
    status_handler(404) do
      { error: 'Not found' }
    end

    # Main routing logic
    route do |r|
      # Debug logging for development
      Onetime.development? do
        http_logger.debug 'Auth router request', {
          method: r.request_method,
          path_info: r.path_info,
          request_uri: r.env['REQUEST_URI'],
          script_name: r.env['SCRIPT_NAME'],
        }
      end

      # Root path - Auth app info
      # When mounted at /auth, this handles requests to /auth and /auth/
      r.is do
        r.get do
          { message: 'OneTimeSecret Authentication Service', version: Onetime::VERSION }
        end
      end

      # All Rodauth routes (login, logout, create-account, reset-password, etc.)
      # Rodauth handles all /auth/* routes when advanced mode is enabled
      r.rodauth

      # Account routes (mfa-status, account info)
      handle_account_routes(r)

      # MFA routes (placeholder - uncomment when implemented)
      # handle_mfa_routes(r)

      # Active sessions routes
      handle_active_sessions_routes(r)

      handle_admin_routes(r)

      handle_health_routes(r)

      # Catch-all for undefined routes
      response.status = 404
      { error: 'Endpoint not found' }
    end

    private

    # # Returns the current customer from session or anonymous
    # # @return [Onetime::Customer]
    # def current_customer
    #   if session['external_id']
    #     Onetime::Customer.find_by_extid(session['external_id'])
    #   else
    #     Onetime::Customer.anonymous
    #   end
    # rescue StandardError => ex
    #   auth_logger.error 'Failed to load customer from session', exception: ex
    #   Onetime::Customer.anonymous
    # end

    # # Returns the current locale for i18n
    # # @return [String]
    # def current_locale
    #   session['locale'] || 'en'
    # end
  end
end
