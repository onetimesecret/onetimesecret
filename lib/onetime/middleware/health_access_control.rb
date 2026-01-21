# lib/onetime/middleware/health_access_control.rb
#
# frozen_string_literal: true

require 'ipaddr'

module Onetime
  module Middleware
    # HealthAccessControl - Restricts health endpoints to localhost/private networks
    #
    # Health check endpoints expose internal system status and should only be
    # accessible from trusted networks (localhost, private IP ranges).
    #
    # Paths covered: /health, /health/*, /auth/health
    #
    class HealthAccessControl
      # RFC 1918 private ranges + loopback + link-local (IPv4 and IPv6)
      PRIVATE_RANGES = [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('127.0.0.0/8'),      # IPv4 loopback
        IPAddr.new('169.254.0.0/16'),   # IPv4 link-local
        IPAddr.new('::1/128'),          # IPv6 loopback
        IPAddr.new('fc00::/7'),         # IPv6 unique local
        IPAddr.new('fe80::/10'),        # IPv6 link-local
      ].freeze

      def initialize(app)
        @app    = app
        @logger = Onetime.get_logger('HealthAccessControl')
      end

      def call(env)
        req  = Rack::Request.new(env)
        path = req.path_info

        # Only apply to health endpoints
        return @app.call(env) unless health_endpoint?(path)

        # Check if request is from localhost/private network
        client_ip = req.ip

        unless private_network?(client_ip)
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

      def private_network?(ip_string)
        return true if ip_string.nil? || ip_string.empty?

        begin
          ip = IPAddr.new(ip_string)
          PRIVATE_RANGES.any? { |range| range.include?(ip) }
        rescue IPAddr::InvalidAddressError
          # Treat invalid IPs as non-private (deny access)
          false
        end
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
