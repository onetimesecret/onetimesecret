# lib/onetime/middleware/security.rb
#
# frozen_string_literal: true

#
# Security middleware collection for the Onetime Secret application.
# Configures various Rack::Protection middleware components based on
# application configuration settings.

require 'rack'
require 'rack/protection'
require 'rack/utf8_sanitizer'

module Onetime
  module Middleware
    # Security middleware collection for Onetime Secret
    #
    # This middleware provides a centralized configuration for various
    # security-related Rack middleware components:
    # - UTF-8 sanitization to prevent encoding-based attacks
    # - Protection against CSRF via HTTP Origin validation
    # - Parameter escaping to prevent XSS attacks
    # - XSS protection headers
    # - Frame options to prevent clickjacking
    # - Path traversal protection
    # - Cookie tossing prevention
    # - IP spoofing protection
    # - Strict Transport Security configuration
    #
    # Each protection can be individually enabled/disabled via configuration.
    #
    class Security
      @middleware_components = {}

      # Middleware keys whose protections are security-critical: switching one of
      # these off silently weakens the app, so a disable is logged at warn level.
      # Toggles that ship OFF by design (http_origin, xss_header, cookie_tossing,
      # ip_spoofing) are intentionally excluded to keep the log quiet.
      SECURITY_CRITICAL_KEYS = %w[
        frame_options
        path_traversal
        strict_transport
        authenticity_token
        utf8_sanitizer
      ].freeze

      # The wrapped Rack application
      # @return [#call] The Rack application instance passed to this middleware
      attr_reader :app

      # Initialize the security middleware
      #
      # @param app [#call] The Rack application to wrap
      def initialize(app)
        @app      = app
        @rack_app = setup_security_middleware
      end

      # Process an HTTP request through the security middleware stack
      #
      # @param env [Hash] Rack environment hash containing request information
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        @rack_app.call(env)
      end

      private

      # Configure the security middleware stack based on application settings
      #
      # Reads configuration from Onetime.conf.dig("site", "middleware")
      # and conditionally enables corresponding Rack::Protection middleware.
      #
      # @return [#call] Configured Rack application with security middleware
      def setup_security_middleware
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance        = @app
        middleware_settings = Onetime.conf.dig('site', 'middleware') || {}

        # Define middleware components with their corresponding settings keys
        components     = self.class.middleware_components
        critical_keys  = SECURITY_CRITICAL_KEYS
        Rack::Builder.new do
          # Apply each middleware if configured
          components.each do |name, config|
            # ERB in the config emits real YAML booleans (true/false), so this
            # reads a real boolean, not a string.
            middleware_key = config[:key].to_s
            unless middleware_settings[middleware_key]
              # Loudly flag a security-critical protection that is switched off so
              # an accidental disable is visible in logs. Deliberately-off toggles
              # stay quiet (see SECURITY_CRITICAL_KEYS).
              if critical_keys.include?(middleware_key)
                OT.lw "[Security] #{name} protection DISABLED (site.middleware.#{middleware_key}=false)"
              end
              next
            end

            OT.ld "[Security] Enabling #{name} protection (site.middleware.#{middleware_key})"

            # Use double-splat to pass options only if they exist
            use config[:klass], **(config[:options] || {})
          end

          # Pass through to original application
          run ->(env) { app_instance.call(env) }
        end.to_app
      end

      class << self
        attr_accessor :middleware_components
      end
    end
  end
end

Onetime::Middleware::Security.middleware_components = {
  # UTF-8 Sanitization: Ensures request parameters use valid UTF-8 encoding.
  'UTF8Sanitizer' => {
    key: :utf8_sanitizer,
    klass: Rack::UTF8Sanitizer,
    options: { sanitize_null_bytes: true },
  },

  # CSRF Protection (Token-based): Validates 'shrimp' authenticity tokens.
  #
  # This middleware validates CSRF tokens for all state-changing requests (POST, PUT, etc.)
  # using Rack::Protection::AuthenticityToken. The raw token is stored in session[:csrf],
  # but forms submit a MASKED version (different each request) to mitigate BREACH attacks.
  #
  # Bypass rules:
  # - SSO routes (/auth/sso/*): Use OAuth 'state' parameter for CSRF protection
  # - API routes WITHOUT an authenticated session cookie: no ambient credential to
  #   forge, so no CSRF vector (Basic-Auth API-key clients, anonymous/programmatic
  #   callers, unauthenticated secret recipients, the /api/incoming/* inbound surface)
  # - Web/SPA + session-authenticated API routes: Must include X-CSRF-Token header
  #   (Axios interceptor) or 'shrimp' form param
  #
  # Note: API v1 has no session/cookie auth (Basic Auth or anonymous only), so v1
  # requests never carry an authenticated session and always bypass. API v2/v3
  # support session auth; a logged-in SPA user hitting those endpoints is required
  # to present a CSRF token (the allow_if lambda enforces this by checking for an
  # authenticated session cookie).
  #
  # See also: apps/web/auth/config/hooks/omniauth.rb for Rodauth-side bypass
  'AuthenticityToken' => {
    key: :authenticity_token,
    klass: Rack::Protection::AuthenticityToken,
    options: {
      authenticity_param: 'shrimp',
      allow_if: ->(env) {
        req = Rack::Request.new(env)

        # SSO routes use OAuth state parameter for CSRF protection
        return true if req.path.start_with?('/auth/sso/')

        # Magic link routes: The email-auth token itself provides CSRF protection
        # - Token is cryptographically random, one-time use, and time-limited
        # - User arrives from external email client without existing session/CSRF token
        # - Similar to SSO: the authentication token validates the request
        return true if req.path == '/auth/email-login'

        # API routes: bypass CSRF ONLY when there is no ambient session cookie to
        # forge against. A CSRF attack rides the victim's session cookie, so the
        # discriminator MUST be the authenticated session — not merely the presence
        # of an Authorization header.
        #   - Basic Auth (API key): a stateless credential sent explicitly per
        #     request; no ambient cookie => no CSRF vector => bypass.
        #   - No authenticated session cookie (anonymous/programmatic clients, v1
        #     which has no session auth, unauthenticated secret recipients, and the
        #     entire /api/incoming/* inbound surface): nothing to forge => bypass.
        #   - Session-cookie-authenticated API request (logged-in SPA user): fall
        #     through and require a valid X-CSRF-Token. The SPA sends it on every
        #     request (axios interceptor), so this does not break the app; it only
        #     rejects a forged cross-site request that presents no token.
        if req.path.start_with?('/api/')
          return true if env['HTTP_AUTHORIZATION'].to_s.start_with?('Basic ')

          session = env['rack.session']
          return true unless session && session['authenticated'] == true
          # else: session-authenticated API request -> fall through, require token
        end

        # NOTE: Incoming secrets API is now at /api/incoming/* and covered by the /api/ check above.
        # The frontend page at /incoming uses GET requests which don't require CSRF protection.

        # Webhook endpoints use their own signature-based verification (e.g., Stripe-Signature header)
        # They're called server-to-server, not from browsers, so CSRF doesn't apply
        return true if req.path == '/billing/webhook'

        false
      },
    },
  },

  # CSRF Protection (Origin-based): Validates Origin and Referer headers.
  'HttpOrigin' => {
    key: :http_origin,
    klass: Rack::Protection::HttpOrigin,
  },

  # NOTE: Rack::Protection::EscapedParams is intentionally EXCLUDED.
  # It escapes all parameters uniformly, which would corrupt sensitive data
  # like passwords and secrets. OTS uses Onetime::Security::InputSanitizers
  # for field-aware sanitization instead.

  # XSS Header: Sets X-XSS-Protection to mitigate reflected XSS in older browsers.
  'XSSHeader' => {
    key: :xss_header,
    klass: Rack::Protection::XSSHeader,
  },

  # Frame Options: Prevents clickjacking by restricting iframe embedding.
  'FrameOptions' => {
    key: :frame_options,
    klass: Rack::Protection::FrameOptions,
  },

  # Path Traversal: Prevents directory traversal attacks in request paths.
  'PathTraversal' => {
    key: :path_traversal,
    klass: Rack::Protection::PathTraversal,
  },

  # Cookie Tossing: Blocks session fixation via cookies set on subdomains.
  'CookieTossing' => {
    key: :cookie_tossing,
    klass: Rack::Protection::CookieTossing,
  },

  # IP Spoofing: Detects and blocks IP spoofing attempts via header validation.
  'IPSpoofing' => {
    key: :ip_spoofing,
    klass: Rack::Protection::IPSpoofing,
  },

  # HSTS: Forces HTTPS by setting the Strict-Transport-Security header.
  'StrictTransport' => {
    key: :strict_transport,
    klass: Rack::Protection::StrictTransport,
  },
}
