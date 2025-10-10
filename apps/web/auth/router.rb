# apps/web/auth/router.rb

require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

require_relative 'config/rodauth_main'
require_relative 'routes/account'
require_relative 'routes/admin'
require_relative 'routes/health'
require_relative 'routes/validation'

module Auth
  # This is the Roda application, which handles all routing for the auth service.
  class Router < Roda
    # Include session validation helpers
    # TODO: Implement these modules
    # include Auth::Helpers::SessionValidation

    # Include route modules
    include Auth::Routes::Health
    include Auth::Routes::Validation
    include Auth::Routes::Account
    include Auth::Routes::Admin

    # Session middleware is now configured globally in MiddlewareStack

    plugin :json
    plugin :halt
    plugin :status_handler

    # Activate Rodauth with configuration from RodauthMain
    plugin :rodauth do
      instance_eval(&Auth::Config::RodauthMain.configure)
    end

    # Status handlers
    status_handler(404) do
      { error: 'Not found' }
    end

    # Main routing logic
    route do |r|
      # Debug logging for development
      Onetime.development? do
        OT.ld "[auth] #{r.request_method} #{r.path_info}"
        OT.ld "  PATH_INFO: '#{r.env['PATH_INFO']}'"
        OT.ld "  REQUEST_URI: '#{r.env['REQUEST_URI']}'"
        OT.ld "  SCRIPT_NAME: '#{r.env['SCRIPT_NAME']}'"
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
      # Health check endpoint
      r.on('health') do
        r.get do
          begin
            # Test database connection if in advanced mode
            db_status = if Onetime.auth_config.advanced_enabled? && Auth::Config::Database.connection
              Auth::Config::Database.connection.test_connection ? 'ok' : 'error'
            else
              'not_required'
            end

            {
              status: 'ok',
              timestamp: Time.now.to_i,
              database: db_status,
              version: Onetime::VERSION,
              mode: Onetime.auth_config.mode
            }
          rescue => e
            response.status = 503
            {
              status: 'error',
              error: e.message,
              timestamp: Time.now.to_i
            }
          end
        end
      end

      # Admin endpoints (if needed)
      r.on('admin') do
        # Add admin authentication here
        r.get('stats') do
          begin
            if Onetime.auth_config.advanced_enabled? && Auth::Config::Database.connection
              db = Auth::Config::Database.connection
              {
                total_accounts: db[:accounts].count,
                verified_accounts: db[:accounts].where(status_id: 2).count,
                active_sessions: db[:account_active_session_keys].count,
                mfa_enabled_accounts: db[:account_otp_keys].count,
                mode: 'advanced'
              }
            else
              {
                mode: 'basic',
                message: 'Stats not available in basic mode'
              }
            end
          rescue => e
            OT.le "Error: #{e.class} - #{e.message}"
            response.status = 500
            { error: 'Internal server error' }
          end
        end
      end
    end

    # Returns the current customer from session or anonymous
    # @return [Onetime::Customer]
    def current_customer
      if session['identity_id']
        Onetime::Customer.find(session['identity_id'])
      else
        Onetime::Customer.anonymous
      end
    rescue StandardError => ex
      OT.le "Failed to load customer: #{ex.message}"
      Onetime::Customer.anonymous
    end

    # Returns the current locale for i18n
    # @return [String]
    def current_locale
      session['locale'] || 'en'
    end
  end
end
