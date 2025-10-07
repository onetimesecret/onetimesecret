# apps/web/auth/router.rb

require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

module Auth
  # This is the Roda application, which handles all routing for the auth service.
  class Router < Roda
    # Include session validation helpers
    # TODO: Implement these modules
    # include Auth::Helpers::SessionValidation

    # Include route modules
    # TODO: Implement these route modules
    # include Auth::Routes::Health
    # include Auth::Routes::Validation
    # include Auth::Routes::Account
    # include Auth::Routes::Admin

    # Session middleware is now configured globally in MiddlewareStack

    plugin :json
    plugin :halt
    plugin :error_handler
    plugin :status_handler

    # Status handlers
    status_handler(404) do
      { error: 'Not found' }
    end

    # Rodauth plugin configuration - only load in advanced mode
    # This ensures basic mode can operate without database dependencies
    if Onetime.auth_config.advanced_enabled?
      plugin :rodauth, &Auth::Config::RodauthMain.configure
    end

    # Main routing logic - handles requests based on authentication mode
    route do |r|
      # Determine authentication mode at request time
      # This allows runtime switching between basic/advanced modes
      auth_mode = Onetime.auth_config.mode

      # Debug logging for development
      Onetime.development? do
        OT.ld "[#{Time.now}] #{r.request_method} #{r.path_info}"
        OT.ld "  PATH_INFO: '#{r.env['PATH_INFO']}'"
        OT.ld "  REQUEST_URI: '#{r.env['REQUEST_URI']}'"
        OT.ld "  SCRIPT_NAME: '#{r.env['SCRIPT_NAME']}'"
        OT.ld "  [Auth] Mode: #{auth_mode}"
      end

      # Handle empty path (when accessed as /auth without trailing slash)
      if r.path_info == ''
        { message: 'OneTimeSecret Authentication Service API', endpoints: %w[/health /validate /account] }
      end

      # Home page - JSON API info
      r.root do
        { message: 'OneTimeSecret Authentication Service API', endpoints: %w[/health /validate /account] }
      end

      # ==============================================================================
      # COMMON ROUTES (available in both basic and advanced modes)
      # ==============================================================================
      # These routes provide core functionality regardless of authentication mode:
      # - Health checks for monitoring
      # - Session validation for frontend auth checks
      # - Account information retrieval
      # - Admin functions for management
      # TODO: Implement these route handlers
      # handle_health_routes(r)
      # handle_validation_routes(r)
      # handle_account_routes(r)
      # handle_admin_routes(r)

      # ==============================================================================
      # MODE-SPECIFIC AUTHENTICATION ROUTING
      # ==============================================================================
      # Route authentication requests differently based on the configured mode
      case auth_mode
      when 'advanced'
        # ADVANCED MODE: Modern database-backed authentication
        # - Uses Rodauth framework for full auth lifecycle
        # - Supports MFA, account recovery, session management
        # - Stores accounts in database with Sequel ORM
        # - Integrates with Otto via external_id linking
        handle_advanced_auth_routes(r)
      when 'basic'
        # BASIC MODE: Legacy Redis-based authentication
        # - Forwards auth requests to Core Web App controllers
        # - Preserves existing V2::Logic authentication classes
        # - Uses Redis sessions with Onetime::Customer objects
        # - Maintains backwards compatibility
        handle_basic_auth_routes(r)
      else
        # Unknown mode - configuration error
        response.status = 503
        return { error: "Unknown authentication mode: #{auth_mode}" }
      end

      # Catch-all for undefined routes - only reached if no routes matched above
      response.status = 404
      { error: 'Endpoint not found' }
    end

    private

    # Handles authentication routes in advanced mode using Rodauth framework
    #
    # Advanced mode provides full authentication lifecycle management:
    # - User registration and account creation
    # - Login/logout with session management
    # - Password reset and change functionality
    # - Multi-factor authentication (MFA) support
    # - Account lockout and security features
    # - Email verification and account management
    #
    # All routes are handled natively by Rodauth without forwarding
    # @param r [Roda::RodaRequest] The current request object
    def handle_advanced_auth_routes(r)
      # Delegate all authentication routes to Rodauth framework
      # This includes: /login, /logout, /create-account, /reset-password, etc.
      # Rodauth automatically handles routing, validation, and responses
      r.rodauth
    end

    # Handles authentication routes in basic mode by forwarding to Core Web App
    #
    # Basic mode preserves backwards compatibility by forwarding auth requests
    # to the existing Core Web App controllers that use V2::Logic classes.
    # This maintains the Redis session + Onetime::Customer architecture.
    #
    # Route Mappings:
    # - /auth/login → Core:/signin (Core::Controllers::Account#authenticate)
    # - /auth/logout → Core:/logout (Core::Controllers::Account#logout)
    # - /auth/create-account → Core:/signup (Core::Controllers::Account#create_account)
    # - /auth/reset-password → Core:/forgot (password reset request)
    # - /auth/reset-password/:key → Core:/forgot/:key (password reset with token)
    #
    # @param r [Roda::RodaRequest] The current request object
    def handle_basic_auth_routes(r)
      OT.li "[Auth] Handling basic auth routes, path: #{r.remaining_path}"

      # Strip the /auth prefix if present (in case URLMap didn't strip it)
      r.on('auth') do
        OT.li "[Auth] Stripping /auth prefix"

        # Map auth service endpoints to core controller paths
        r.on('login') do
          OT.li "[Auth] Matched 'login' path segment"
          r.is do
            OT.li "[Auth] Forwarding login to /signin"
            forward_to_core_auth('/signin', r)
          end
        end

        r.on('logout') do
          r.is do
            forward_to_core_auth('/logout', r)
          end
        end

        r.on('create-account') do
          r.is do
            forward_to_core_auth('/signup', r)
          end
        end

        # Password reset routes
        r.on('reset-password') do
          # Handle both forms:
          # - /auth/reset-password (request reset email)
          # - /auth/reset-password/:key (reset with token)
          r.is String do |key|
            # Reset with token key
            forward_to_core_auth("/forgot/#{key}", r)
          end

          r.is do
            # Request reset email
            forward_to_core_auth('/forgot', r)
          end
        end
      end

      # Other auth routes are not handled in basic mode
      # This ensures clean separation between modes
      nil
    end

    # Forwards authentication requests to the Core Web App controllers
    #
    # This method creates a proxy between the Auth Service and Core Web App,
    # allowing basic mode to reuse existing authentication logic while
    # maintaining the new auth service API endpoints.
    #
    # Process:
    # 1. Modify request environment to target the core controller path
    # 2. Retrieve Core Web App instance from AppRegistry
    # 3. Forward the modified request to core app
    # 4. Handle response based on content type (JSON, redirects, HTML)
    # 5. Convert responses to JSON format for API consistency
    #
    # @param path [String] The target path in the core app (e.g., '/signin')
    # @param r [Roda::RodaRequest] The current request object
    # @return [Hash, String, nil] JSON response, HTML content, or nil for redirects
    def forward_to_core_auth(path, r)
      # Step 1: Modify request environment to target core controller path
      new_env                = r.env.dup
      new_env['PATH_INFO']   = path
      # REQUEST_URI might not be set (depends on web server)
      if new_env['REQUEST_URI']
        new_env['REQUEST_URI'] = new_env['REQUEST_URI'].sub(r.path_info, path)
      else
        new_env['REQUEST_URI'] = path
      end

      # Ensure parameters are properly passed through
      # The Vue frontend sends: u (email), p (password), shrimp (CSRF token)
      # The Core app expects the same parameter names, so no mapping needed

      # Step 2: Retrieve Core Web App instance
      core_app = get_core_web_app

      if core_app
        # Step 3: Forward the modified request to core app
        status, headers, body = core_app.call(new_env)

        # Step 4: Set response status and headers
        response.status                           = status
        headers.each { |k, v| response.headers[k] = v unless k.downcase == 'content-length' }

        # Step 5: Handle response based on content type for API consistency
        if headers['Content-Type']&.include?('application/json')
          # Already JSON - parse and return
          body_str = body.is_a?(Array) ? body.join : body.to_s
          begin
            JSON.parse(body_str)
          rescue JSON::ParserError
            { error: 'Invalid JSON response from core auth' }
          end
        elsif status >= 300 && status < 400 && headers['Location']
          # Convert redirects to JSON for Vue frontend
          # Core auth redirects on success - convert to JSON response
          location = headers['Location']

          # Successful authentication redirects to '/' or '/colonel/'
          if ['/signin', '/login'].include?(path) && (['/', '/colonel/'].include?(location))
            response.status                  = 200
            response.headers['Content-Type'] = 'application/json'
            { success: true, redirect: location, authenticated: true }
          # Successful registration/signup redirects
          elsif path == '/signup' && location == '/'
            response.status                  = 200
            response.headers['Content-Type'] = 'application/json'
            { success: true, redirect: location, message: 'Account created successfully' }
          # Successful logout
          elsif path == '/logout' && location
            response.status                  = 200
            response.headers['Content-Type'] = 'application/json'
            { success: true, redirect: location, authenticated: false }
          else
            # Generic redirect handling
            response.status                  = 200
            response.headers['Content-Type'] = 'application/json'
            { success: true, redirect: location }
          end
        elsif status >= 400
          # Error responses - convert to JSON
          body_str = body.is_a?(Array) ? body.join : body.to_s

          # Try to extract error message from HTML response
          error_msg = if body_str.include?('Try again')
                        'Invalid email or password'
                      elsif body_str.include?('already exists')
                        'An account with that email already exists'
                      else
                        'Authentication failed'
                      end

          response.status                  = status
          response.headers['Content-Type'] = 'application/json'
          { success: false, error: error_msg }
        else
          # Return HTML or other content as-is (shouldn't happen for auth endpoints)
          body.is_a?(Array) ? body.join : body.to_s
        end
      else
        # Core app unavailable - service degraded
        response.status                  = 503
        response.headers['Content-Type'] = 'application/json'
        { error: 'Authentication service unavailable' }
      end
    end

    # Retrieves the Core Web App instance from the application registry
    #
    # The Core Web App is responsible for handling authentication in basic mode.
    # This method safely attempts to access the core app through the AppRegistry
    # system, which manages the mapping between URL paths and application classes.
    #
    # @return [Object, nil] The Core Web App instance, or nil if unavailable
    def get_core_web_app
      # Access the Core Web App through the application registry
      if defined?(Onetime::Application::Registry)
        # Ensure the registry is prepared (this is idempotent)
        if Onetime::Application::Registry.mount_mappings.empty?
          Onetime::Application::Registry.prepare_application_registry
        end

        core_app_class = Onetime::Application::Registry.mount_mappings['/']
        core_app_class&.new
      end
    rescue StandardError => ex
      # Log error in development but don't expose details in production
      OT.le "Error getting core app: #{ex.message}"
      OT.ld ex.backtrace.join("\n")
      nil
    end
  end
end
