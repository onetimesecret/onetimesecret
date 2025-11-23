# lib/onetime/middleware/ip_ban.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # IPBan - Middleware to block requests from banned IP addresses
    #
    # This middleware checks if the request's IP address is in the banned IPs list
    # and returns a 403 Forbidden response if it is.
    #
    class IPBan
      def initialize(app)
        @app = app
        @logger = Onetime.get_logger('IPBan')
      end

      def call(env)
        # Get the client IP address
        ip_address = get_client_ip(env)

        # Check if IP is banned
        if ip_address && Onetime::BannedIP.banned?(ip_address)
          @logger.warn 'Blocked request from banned IP', {
            ip: ip_address,
            path: env['PATH_INFO'],
            method: env['REQUEST_METHOD'],
          }

          return [
            403,
            { 'Content-Type' => 'application/json' },
            [JSON.generate({ error: 'Access forbidden', message: 'Your IP address has been banned' })],
          ]
        end

        @app.call(env)
      end

      private

      def get_client_ip(env)
        # Try to get the real IP from X-Forwarded-For or X-Real-IP headers
        # Fall back to REMOTE_ADDR if not available
        env['HTTP_X_FORWARDED_FOR']&.split(',')&.first&.strip ||
          env['HTTP_X_REAL_IP'] ||
          env['REMOTE_ADDR']
      end
    end
  end
end
