# frozen_string_literal: true

# RequestSetup middleware handles request-level initialization for Web Core.
#
# Responsibilities:
# - Generate CSP nonce and make available to views via req.env['ots.nonce']
# - Set default Content-Type if not already set
# - Initialize locale from request
#
# This middleware should run after session middleware but before authentication
# and error handling middleware.

module Core
  module Middleware
    class RequestSetup
      def initialize(app, default_content_type: 'text/html; charset=utf-8')
        @app = app
        @default_content_type = default_content_type
      end

    def call(env)
      setup_request(env)
      status, headers, body = @app.call(env)
      finalize_response(status, headers, body, env)
    end

    private

    def setup_request(env)
      # Generate unique nonce for CSP headers (used by views)
      nonce = SecureRandom.base64(16)
      env['ots.nonce'] = nonce

      # Set locale from request (used by views and controllers)
      env['ots.locale'] = extract_locale(env)

      OT.ld "[middleware] RequestSetup: locale=#{env['ots.locale']} nonce=#{nonce[0, 8]}..." if OT.debug?
    end

    def finalize_response(status, headers, body, env)
      # Set default Content-Type if not already set
      headers['content-type'] ||= @default_content_type

      [status, headers, body]
    end

    def extract_locale(env)
      # Try params first
      req = Rack::Request.new(env)
      locale = req.params['locale']
      return locale if locale && valid_locale?(locale)

      # Try session
      session = env['rack.session']
      locale = session['locale'] if session
      return locale if locale && valid_locale?(locale)

      # Try Accept-Language header
      locale = parse_accept_language(env['HTTP_ACCEPT_LANGUAGE'])
      return locale if locale && valid_locale?(locale)

      # Default to English
      'en'
    end

    def parse_accept_language(header)
      return nil unless header

      # Parse Accept-Language header (e.g., "en-US,en;q=0.9,fr;q=0.8")
      # Take first language code
      lang = header.split(',').first
      return nil unless lang

      # Extract language code (e.g., "en-US" -> "en")
      lang.split('-').first.downcase
    rescue StandardError => ex
      OT.le "[middleware] RequestSetup: Failed to parse Accept-Language: #{ex.message}"
      nil
    end

    def valid_locale?(locale)
      # Add more locales as they become available
      %w[en es fr de it ja ko pt ru zh].include?(locale.to_s.downcase)
    end
    end
  end
end
