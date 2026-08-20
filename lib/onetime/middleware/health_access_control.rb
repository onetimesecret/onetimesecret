# lib/onetime/middleware/health_access_control.rb
#
# frozen_string_literal: true

require 'otto/utils'

module Onetime
  module Middleware
    # HealthAccessControl - Restricts health endpoints to localhost/private networks
    #
    # Health check endpoints expose internal system status and should only be
    # accessible from trusted networks (localhost, private IP ranges).
    #
    # Paths covered (MOUNT-RELATIVE): /health and /health/*
    #
    # This middleware runs inside Rack::URLMap, once per mounted app, so
    # PATH_INFO here has the mount prefix stripped. In full auth mode the auth
    # app's health check is externally /auth/health but arrives as
    # SCRIPT_NAME='/auth' + PATH_INFO='/health' — covered by the /health
    # branch, not by any '/auth/health' literal. In simple/disabled modes the
    # auth app is unmounted, so /auth/health falls through to the core app
    # (PATH_INFO='/auth/health') where no route serves it: it passes this
    # middleware unmatched and 404s at the router, disclosing nothing.
    #
    # Matching is on the NORMALIZED path (Otto::Utils.normalize_path), the
    # same canonicalization the Otto router applies before dispatch — see
    # health_endpoint?.
    #
    # Uses Otto::Privacy::IPPrivacy.private_or_localhost? which covers:
    # - RFC 1918 (10/8, 172.16/12, 192.168/16)
    # - IPv4/IPv6 loopback (127/8, ::1)
    # - IPv6 private ranges (fc00::/7, fe80::/10)
    #
    # Optionally allows extra CIDR ranges via HEALTH_TRUSTED_CIDR env var
    # (comma-separated, e.g. "100.64.0.0/10,10.96.0.0/12").
    # When unset, only RFC 1918 and loopback addresses are trusted.
    #
    class HealthAccessControl
      def initialize(app)
        @app          = app
        @logger       = Onetime.get_logger('HealthAccessControl')
        @extra_ranges = parse_trusted_cidrs(ENV.fetch('HEALTH_TRUSTED_CIDR', nil))
      end

      def call(env)
        path = env['PATH_INFO']

        return @app.call(env) unless health_endpoint?(path)

        client_ip = Rack::Request.new(env).ip

        unless trusted_ip?(client_ip)
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

      def trusted_ip?(client_ip)
        Otto::Privacy::IPPrivacy.private_or_localhost?(client_ip) ||
          extra_range?(client_ip)
      rescue StandardError
        false
      end

      def extra_range?(client_ip)
        return false if client_ip.nil? || client_ip.empty?

        addr = IPAddr.new(client_ip)
        @extra_ranges.any? { |range| range.include?(addr) }
      rescue IPAddr::InvalidAddressError
        false
      end

      def parse_trusted_cidrs(value)
        return [] if value.nil? || value.strip.empty?

        value.split(',').filter_map do |cidr|
          IPAddr.new(cidr.strip)
        rescue IPAddr::InvalidAddressError
          @logger.warn "Invalid CIDR in HEALTH_TRUSTED_CIDR, skipping: #{cidr.strip}"
          nil
        end
      end

      # `path` is PATH_INFO, i.e. mount-relative (the URLMap prefix lives in
      # SCRIPT_NAME). So '/health' covers every app's health endpoint whatever
      # it is mounted under, including the auth app's external /auth/health in
      # full mode. No mounted app ROUTES a PATH_INFO of '/auth/health' (in
      # non-full modes the request reaches core unmatched and 404s at the
      # router), so a literal '/auth/health' branch would only gate a 404.
      #
      # Normalize before matching, with the same canonicalization the Otto
      # router applies before dispatch: the router serves `/health/` and
      # percent-encoded spellings like `/health%2Fadvanced` as health routes,
      # so gating the raw string would let those aliases through to the
      # handler ungated.
      def health_endpoint?(path)
        normalized = Otto::Utils.normalize_path(path)
        normalized == '/health' || normalized.start_with?('/health/')
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
