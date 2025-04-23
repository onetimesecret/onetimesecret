# lib/onetime/middleware/security.rb
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
      # The wrapped Rack application
      # @return [#call] The Rack application instance passed to this middleware
      attr_reader :app

      # Initialize the security middleware
      #
      # @param app [#call] The Rack application to wrap
      def initialize(app)
        @app = app
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
      # Reads configuration from Onetime.conf.dig(:experimental, :middleware)
      # and conditionally enables corresponding Rack::Protection middleware.
      #
      # @return [#call] Configured Rack application with security middleware
      def setup_security_middleware
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance = @app
        middleware_settings = Onetime.conf.dig(:experimental, :middleware)

        Rack::Builder.new do
          # Get middleware configuration from application settings
          if middleware_settings
            # UTF-8 Sanitization - Ensures proper UTF-8 encoding in request parameters
            if middleware_settings[:utf8_sanitizer]
              Onetime.ld "[Security] Enabling UTF8Sanitizer middleware"
              use Rack::UTF8Sanitizer, sanitize_null_bytes: true
            end

            # Protection against CSRF attacks
            if middleware_settings[:http_origin]
              Onetime.ld "[Security] Enabling HttpOrigin protection"
              use Rack::Protection::HttpOrigin
            end

            # Escapes HTML in parameters to prevent XSS
            if middleware_settings[:escaped_params]
              Onetime.ld "[Security] Enabling EscapedParams protection"
              use Rack::Protection::EscapedParams
            end

            # Sets X-XSS-Protection header
            if middleware_settings[:xss_header]
              Onetime.ld "[Security] Enabling XSSHeader protection"
              use Rack::Protection::XSSHeader
            end

            # Prevents clickjacking via X-Frame-Options
            if middleware_settings[:frame_options]
              Onetime.ld "[Security] Enabling FrameOptions protection"
              use Rack::Protection::FrameOptions
            end

            # Blocks directory traversal attacks
            if middleware_settings[:path_traversal]
              Onetime.ld "[Security] Enabling PathTraversal protection"
              use Rack::Protection::PathTraversal
            end

            # Prevents session fixation via manipulated cookies
            if middleware_settings[:cookie_tossing]
              Onetime.ld "[Security] Enabling CookieTossing protection"
              use Rack::Protection::CookieTossing
            end

            # Prevents IP spoofing attacks
            if middleware_settings[:ip_spoofing]
              Onetime.ld "[Security] Enabling IPSpoofing protection"
              use Rack::Protection::IPSpoofing
            end

            # Forces HTTPS connections via HSTS headers
            if middleware_settings[:strict_transport]
              Onetime.ld "[Security] Enabling StrictTransport protection"
              use Rack::Protection::StrictTransport
            end
          end

          # All requests eventually pass through to the original application
          run ->(env) { app_instance.call(env) }
        end.to_app
      end
    end
  end
end
