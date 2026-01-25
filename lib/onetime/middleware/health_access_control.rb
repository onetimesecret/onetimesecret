# lib/onetime/middleware/health_access_control.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # HealthAccessControl - Restricts health endpoints to localhost/private networks
    #
    # Health check endpoints expose internal system status and should only be
    # accessible from trusted networks (localhost, private IP ranges).
    #
    # Paths covered: /health, /health/*, /auth/health
    #
    # Uses Otto::Privacy::IPPrivacy.private_or_localhost? which covers:
    # - RFC 1918 (10/8, 172.16/12, 192.168/16)
    # - IPv4/IPv6 loopback (127/8, ::1)
    # - IPv6 private ranges (fc00::/7, fe80::/10)
    #
    class HealthAccessControl
      def initialize(app)
        @app    = app
        @logger = Onetime.get_logger('HealthAccessControl')
      end

      def call(env)
        path = env['PATH_INFO']

        return @app.call(env) unless health_endpoint?(path)

        client_ip = Rack::Request.new(env).ip

        unless Otto::Privacy::IPPrivacy.private_or_localhost?(client_ip)
          @logger.warn 'Health endpoint access denied',
            {
              ip: client_ip,
              path: path,
              method: env['REQUEST_METHOD'],
            }

          return forbidden_response
        end

        @app.call(env)
      end

      private

      def health_endpoint?(path)
        path == '/health' ||
          path.start_with?('/health/') ||
          path == '/auth/health'
      end

      def forbidden_response
        [
          403,
          { 'Content-Type' => 'application/json' },
          [JSON.generate({ error: 'Health endpoints restricted to private networks' })],
        ]
      end
    end
  end
end
