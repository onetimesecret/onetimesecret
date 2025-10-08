# apps/web/auth/router.rb

require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

require_relative 'account'
require_relative 'admin'
require_relative 'health'
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
    plugin :error_handler
    plugin :status_handler

    # Error handler for FormError and other exceptions
    error_handler do |e|
      case e
      when Onetime::FormError
        response.status = 422
        { success: false, error: e.message, form_fields: e.form_fields }
      else
        OT.le "[auth] Unhandled error: #{e.class} - #{e.message}"
        OT.le e.backtrace.join("\n") if Onetime.development?
        response.status = 500
        { success: false, error: 'Internal server error' }
      end
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

      # Handle empty path (when accessed as /auth without trailing slash)
      if r.path_info == ''
        { message: 'OneTimeSecret Authentication Service', version: Onetime::VERSION }
      end

      # Home page - JSON API info
      r.root do
        { message: 'OneTimeSecret Authentication Service', version: Onetime::VERSION }
      end

      # Authentication routes - call V2::Logic classes directly
      handle_auth_routes(r)

      # Catch-all for undefined routes
      response.status = 404
      { error: 'Endpoint not found' }
    end

    private

    # Handles all authentication routes by calling V2::Logic classes directly
    #
    # Uses the same V2::Logic classes that the Core Web App controllers use.
    # This maintains the Redis session + Onetime::Customer architecture.
    #
    # Route Implementations:
    # - /login → V2::Logic::Authentication::AuthenticateSession
    # - /logout → V2::Logic::Authentication::DestroySession
    # - /create-account → V2::Logic::Account::CreateAccount
    # - /reset-password → V2::Logic::Authentication::ResetPasswordRequest
    # - /reset-password/:key → V2::Logic::Authentication::ResetPassword
    #
    # @param r [Roda::RodaRequest] The current request object
    def handle_auth_routes(r)
      # Login endpoint
      r.on('login') do
        r.post do
          strategy_result = build_strategy_result
          logic           = V2::Logic::Authentication::AuthenticateSession.new(strategy_result, r.params, current_locale)

          logic.raise_concerns
          logic.process

          # Return JSON response for Vue frontend
          if logic.cust && !logic.cust.anonymous?
            redirect_path = logic.cust.role?(:colonel) ? '/colonel/' : '/'
            { success: true, authenticated: true, redirect: redirect_path }
          else
            response.status = 401
            { success: false, error: 'Invalid email or password' }
          end
        end
      end

      # Logout endpoint
      r.on('logout') do
        r.is do
          strategy_result = build_strategy_result
          logic           = V2::Logic::Authentication::DestroySession.new(strategy_result, r.params, current_locale)

          logic.raise_concerns
          logic.process

          { success: true, authenticated: false, redirect: '/' }
        end
      end

      # Account creation endpoint
      r.on('create-account') do
        r.post do
          strategy_result = build_strategy_result
          logic           = V2::Logic::Account::CreateAccount.new(strategy_result, r.params, current_locale)

          logic.raise_concerns
          logic.process

          { success: true, redirect: '/', message: 'Account created successfully' }
        end
      end

      # Password reset routes
      r.on('reset-password') do
        # Reset with token
        r.is String do |key|
          r.post do
            strategy_result = build_strategy_result
            params_with_key = r.params.merge(key: key)
            logic           = V2::Logic::Authentication::ResetPassword.new(strategy_result, params_with_key, current_locale)

            logic.raise_concerns
            logic.process

            { success: true, redirect: '/signin', message: 'Password reset successfully' }
          end
        end

        # Request reset email
        r.post do
          strategy_result = build_strategy_result
          logic           = V2::Logic::Authentication::ResetPasswordRequest.new(strategy_result, r.params, current_locale)

          logic.raise_concerns
          logic.process

          { success: true, redirect: '/', message: 'Password reset email sent' }
        end
      end

      # No match - will fall through to catch-all 404
      nil
    end

    # Builds an Otto StrategyResult for Logic class compatibility
    #
    # The V2::Logic classes expect an Otto::Security::Authentication::StrategyResult
    # containing session, user, and metadata. This helper constructs that object.
    #
    # @return [Otto::Security::Authentication::StrategyResult]
    def build_strategy_result
      Otto::Security::Authentication::StrategyResult.new(
        session: session,
        user: current_customer,
        auth_method: 'session',
        metadata: {
          ip: request.ip,
          user_agent: request.user_agent,
        },
      )
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
