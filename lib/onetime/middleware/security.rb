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
      @middleware_components = {}

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
      # Reads configuration from Onetime.conf.dig("experimental", "middleware")
      # and conditionally enables corresponding Rack::Protection middleware.
      #
      # @return [#call] Configured Rack application with security middleware
      def setup_security_middleware
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance = @app
        middleware_settings = Onetime.conf.dig("experimental", "middleware") || {}

        # Define middleware components with their corresponding settings keys
        components = self.class.middleware_components
        Rack::Builder.new do
          # Apply each middleware if configured
          components.each do |name, config|
            next unless middleware_settings[config[:key]]
            Onetime.ld "[Security] Enabling #{name} protection"
            if config[:options]
              use config[:klass], config[:options]
            else
              use config[:klass]
            end
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
  # UTF-8 Sanitization - Ensures proper UTF-8 encoding in request parameters
  "UTF8Sanitizer" => {
    key: :utf8_sanitizer,
    klass: Rack::UTF8Sanitizer,
    options: { sanitize_null_bytes: true },
  },
  # Protection against CSRF attacks
  "HttpOrigin" => {
    key: :http_origin,
    klass: Rack::Protection::HttpOrigin,
  },
  # Escapes HTML in parameters to prevent XSS
  "EscapedParams" => {
    key: :escaped_params,
    klass: Rack::Protection::EscapedParams,
  },
  # Sets X-XSS-Protection header
  "XSSHeader" => {
    key: :xss_header,
    klass: Rack::Protection::XSSHeader,
  },
  # Prevents clickjacking via X-Frame-Options
  "FrameOptions" => {
    key: :frame_options,
    klass: Rack::Protection::FrameOptions,
  },
  # Blocks directory traversal attacks
  "PathTraversal" => {
    key: :path_traversal,
    klass: Rack::Protection::PathTraversal,
  },
  # Prevents session fixation via manipulated cookies
  "CookieTossing" => {
    key: :cookie_tossing,
    klass: Rack::Protection::CookieTossing,
  },
  # Prevents IP spoofing attacks
  "IPSpoofing" => {
    key: :ip_spoofing,
    klass: Rack::Protection::IPSpoofing,
  },
  # Forces HTTPS connections via HSTS headers
  "StrictTransport" => {
    key: :strict_transport,
    klass: Rack::Protection::StrictTransport,
  },
}
