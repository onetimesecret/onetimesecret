# apps/web/auth/router.rb

require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

require 'onetime/logging'

require_relative 'config'
require_relative 'routes/account'
require_relative 'routes/admin'
require_relative 'routes/health'
require_relative 'routes/mfa_recovery'
require_relative 'routes/validation'

module Auth
  # This is the Roda application, which handles all routing for the auth service.
  class Router < Roda
    include Onetime::Logging

    # Include session validation helpers
    # TODO: Implement these modules
    # include Auth::Helpers::SessionValidation

    # Include route modules
    include Auth::Routes::Health
    include Auth::Routes::Validation
    include Auth::Routes::Account
    include Auth::Routes::Admin
    include Auth::Routes::MfaRecovery

    # Session middleware is now configured globally in MiddlewareStack

    plugin :json
    plugin :halt
    plugin :status_handler

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
        http_logger.debug 'Auth router request',
          method: r.request_method,
          path_info: r.path_info,
          request_uri: r.env['REQUEST_URI'],
          script_name: r.env['SCRIPT_NAME']
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

      # Additional custom routes can be added here
      handle_custom_routes(r)

      # Catch-all for undefined routes
      response.status = 404
      { error: 'Endpoint not found' }
    end

    private

    # Handle any custom routes beyond standard Rodauth endpoints
    def handle_custom_routes(r)
      # MFA recovery routes
      handle_mfa_recovery_routes(r)

      # Account routes (mfa-status, account info)
      handle_account_routes(r)

      # Health check endpoint
      r.on('health') do
        r.get do
            # Test database connection if in advanced mode
            db_status = if Auth::Database.connection
              Auth::Database.connection.test_connection ? 'ok' : 'error'
            else
              'not_required'
            end

            {
              status: 'ok',
              timestamp: Familia.now.to_i,
              database: db_status,
              version: Onetime::VERSION,
              mode: Onetime.auth_config.mode,
            }
          rescue StandardError => ex
            response.status = 503
            {
              status: 'error',
              error: ex.message,
              timestamp: Familia.now.to_i,
            }
        end
      end

      # Admin endpoints (if needed)
      r.on('admin') do
        # Add admin authentication here
        r.get('stats') do
            db = Auth::Database.connection
            if db
              {
                total_accounts: db[:accounts].count,
                verified_accounts: db[:accounts].where(status_id: 2).count,
                active_sessions: db[:account_active_session_keys].count,
                mfa_enabled_accounts: db[:account_otp_keys].count,
                mode: 'advanced',
              }
            else
              {
                mode: 'basic',
                message: 'Stats not available',
              }
            end
          rescue StandardError => ex
            auth_logger.error 'Auth stats endpoint error', exception: ex
            response.status = 500
            { error: 'Internal server error' }
        end
      end
    end

    # Returns the current customer from session or anonymous
    # @return [Onetime::Customer]
    def current_customer
      if session['external_id']
        Onetime::Customer.find_by_extid(session['external_id'])
      else
        Onetime::Customer.anonymous
      end
    rescue StandardError => ex
      auth_logger.error 'Failed to load customer from session', exception: ex
      Onetime::Customer.anonymous
    end

    # Returns the current locale for i18n
    # @return [String]
    def current_locale
      session['locale'] || 'en'
    end
  end
end
