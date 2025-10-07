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
    include Auth::Helpers::SessionValidation

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

    # Status handlers
    status_handler(404) do
      { error: 'Not found' }
    end

    # Rodauth plugin configuration
    plugin :rodauth, &Auth::Config::RodauthMain.configure

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
      if r.path_info == ""
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
      handle_health_routes(r)
      handle_validation_routes(r)
      handle_account_routes(r)
      handle_admin_routes(r)

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
        { error: "Unknown authentication mode: #{auth_mode}" }
      end

      # Catch-all for undefined routes
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
    #
    # @param r [Roda::RodaRequest] The current request object
    def handle_basic_auth_routes(r)
      # Map auth service endpoints to core controller paths
      r.on('login') do
        forward_to_core_auth('/signin', r)
      end

      r.on('logout') do
        forward_to_core_auth('/logout', r)
      end

      r.on('create-account') do
        forward_to_core_auth('/signup', r)
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
      new_env = r.env.dup
      new_env['PATH_INFO'] = path
      new_env['REQUEST_URI'] = new_env['REQUEST_URI'].sub(r.path_info, path)

      # Step 2: Retrieve Core Web App instance
      core_app = get_core_web_app

      if core_app
        # Step 3: Forward the modified request to core app
        status, headers, body = core_app.call(new_env)

        # Step 4: Set response status and headers
        response.status = status
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
          # Convert redirects to JSON for API consistency
          if r.env['HTTP_ACCEPT']&.include?('application/json')
            { success: true, redirect: headers['Location'] }
          else
            # Honor redirect for browser requests
            response.redirect(headers['Location'])
            nil
          end
        else
          # Return HTML or other content as-is
          body.is_a?(Array) ? body.join : body.to_s
        end
      else
        # Core app unavailable - service degraded
        response.status = 503
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
      if defined?(Onetime::Application::Registry) && Onetime::Application::Registry.respond_to?(:mount_mappings)
        core_app_class = Onetime::Application::Registry.mount_mappings['/']
        core_app_class&.new
      end
    rescue StandardError => e
      # Log error in development but don't expose details in production
      puts "Error getting core app: #{e.message}" if ENV['RACK_ENV'] == 'development'
      nil
    end
  end
end
