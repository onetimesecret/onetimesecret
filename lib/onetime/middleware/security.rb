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
        components = self.class.middleware_components
        Rack::Builder.new do
          # Apply each middleware if configured
          components.each do |name, config|
            # All settings comfing from yaml are strings as a rule
            middleware_key = config[:key].to_s
            next unless middleware_settings[middleware_key]

            OT.ld "[Security] Enabling #{name}/middleware_key protection"

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
  # - API routes with Basic Auth: API key serves as the credential; no session = no CSRF needed
  # - Web/SPA routes: Must include X-CSRF-Token header (Axios interceptor) or 'shrimp' form param
  #
  # Note: API v1 no longer accepts session/cookie auth. Requests must use Basic Auth or be
  # anonymous. This eliminates the CSRF attack vector for API routes.
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

        # API routes with Basic Auth don't need CSRF (API key is the credential)
        # Session-based API requests would need CSRF, but we removed session auth from v1
        if req.path.start_with?('/api/')
          auth = env['otto.auth'] ||= Rack::Auth::Basic::Request.new(env)
          return auth.provided? && auth.basic?
        end

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
