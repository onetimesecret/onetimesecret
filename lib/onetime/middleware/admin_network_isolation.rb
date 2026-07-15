# lib/onetime/middleware/admin_network_isolation.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # AdminNetworkIsolation - Optional network-level isolation for the Colonel
    # admin surfaces (`/colonel` shell + `/api/colonel` API).
    #
    # A sibling of IPBan and HealthAccessControl in the universal middleware
    # stack (see Onetime::Application::MiddlewareStack.configure). It gives the
    # deployment a config-selectable network posture WITHOUT forking the code:
    #
    #   - Self-hosted single-container default: `site.admin.allowed_cidrs` is
    #     unset/empty, so this middleware is a strict NO-OP. Both admin surfaces
    #     remain reachable and the two app-layer auth layers (role=colonel at the
    #     Otto router + verify_one_of_roles!(colonel:true) in each logic class)
    #     are the sole gate — exactly as before.
    #
    #   - Cloud / VPN posture: `site.admin.allowed_cidrs` is set to the private
    #     ranges the admin surfaces should be reachable from (e.g. Tailscale
    #     CGNAT 100.64.0.0/10, an office VPN CIDR, or RFC1918). A request whose
    #     resolved client IP is OUTSIDE the allowlist gets a 404 on `/colonel`
    #     and `/api/colonel` — indistinguishable-from-absent, NOT a 403, so the
    #     admin surface does not even advertise its existence to an unauthorized
    #     network. This is defense-in-depth ON TOP OF the two auth layers, which
    #     still enforce beneath it for any request that does pass the CIDR gate.
    #
    # ## Client IP resolution
    #
    # The allowlist check MUST use the trusted-proxy-resolved client IP, never a
    # raw forwarding header, or the allowlist is trivially spoofable by sending
    # `X-Forwarded-For: <an-allowed-ip>`. We resolve from the canonical
    # env['otto.client_ip'] set once by the universal IPPrivacyMiddleware mount
    # (configured from site.network.trusted_proxy via
    # MiddlewareStack.ip_privacy_security_config), with the same
    # Otto::Utils.resolve_client_ip fallback the auth strategies use. This is the
    # identical resolution the rest of the stack relies on, so the network gate
    # agrees with ban checks, sessions, and audit attribution. When the IP cannot
    # be resolved and an allowlist is configured, the request is denied (404) —
    # fail closed.
    #
    # ## Path matching
    #
    # This middleware runs INSIDE each app, after Rack::URLMap has stripped the
    # mount prefix into SCRIPT_NAME. The colonel API app is mounted at
    # `/api/colonel` (PATH_INFO becomes `/info`, `/stats`, …) and the core web
    # app at `/` (PATH_INFO stays `/colonel`). We reconstruct the full request
    # path from SCRIPT_NAME + PATH_INFO so both surfaces match regardless of
    # which app is handling the request.
    #
    class AdminNetworkIsolation
      def initialize(app)
        @app             = app
        @logger          = Onetime.get_logger('AdminNetworkIsolation')
        @allowed_ranges  = parse_allowed_cidrs(configured_cidrs)

        return if @allowed_ranges.empty?

        @logger.info 'Admin network isolation enabled',
          {
            allowed_cidrs: @allowed_ranges.map(&:to_s),
            surfaces: %w[/colonel /api/colonel],
          }
      end

      def call(env)
        # NO-OP when no allowlist is configured — the self-hosted default.
        return @app.call(env) if @allowed_ranges.empty?

        full_path = request_path(env)
        return @app.call(env) unless admin_surface?(full_path)

        client_ip = resolve_client_ip(env)

        return @app.call(env) if allowed?(client_ip)

        @logger.warn 'Admin surface access denied by network isolation',
          {
            ip: client_ip,
            path: full_path,
            method: env['REQUEST_METHOD'],
          }

        not_found_response(full_path)
      end

      private

      # Full request path independent of where the app is mounted. Rack::URLMap
      # moves the mount prefix into SCRIPT_NAME, so PATH_INFO alone would be
      # `/info` inside the colonel API app (mounted at /api/colonel).
      def request_path(env)
        "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}"
      end

      def admin_surface?(path)
        colonel_shell?(path) || colonel_api?(path)
      end

      def colonel_shell?(path)
        path == '/colonel' || path.start_with?('/colonel/')
      end

      def colonel_api?(path)
        path == '/api/colonel' || path.start_with?('/api/colonel/')
      end

      def allowed?(client_ip)
        return false if client_ip.nil? || client_ip.empty?

        addr = IPAddr.new(client_ip)
        @allowed_ranges.any? { |range| range.include?(addr) }
      rescue IPAddr::InvalidAddressError
        false
      end

      # Resolve the client IP from the trusted-proxy-aware canonical value, with
      # the same fallback the auth strategies use. Never trusts a raw header.
      def resolve_client_ip(env)
        canonical = env['otto.client_ip']
        return canonical if canonical && !canonical.empty?

        Otto::Utils.resolve_client_ip(env, env['otto.security_config'])
      rescue StandardError => ex
        @logger.warn "Client IP resolution failed; denying admin surface: #{ex.message}"
        nil
      end

      def configured_cidrs
        OT.conf.dig('site', 'admin', 'allowed_cidrs')
      rescue StandardError
        nil
      end

      def parse_allowed_cidrs(value)
        Array(value).filter_map do |cidr|
          next if cidr.to_s.strip.empty?

          IPAddr.new(cidr.to_s.strip)
        rescue IPAddr::InvalidAddressError
          @logger.warn "Invalid CIDR in site.admin.allowed_cidrs, skipping: #{cidr}"
          nil
        end
      end

      # 404, not 403: the surface must be indistinguishable from absent to an
      # unauthorized network. Content type mirrors the surface (JSON for the API,
      # HTML for the shell) so the response looks like a normal not-found.
      def not_found_response(path)
        if path.start_with?('/api')
          [
            404,
            { 'Content-Type' => 'application/json' },
            [JSON.generate({ error: 'Not Found' })],
          ]
        else
          [
            404,
            { 'Content-Type' => 'text/html; charset=utf-8' },
            [html_body],
          ]
        end
      end

      def html_body
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>404 Not Found</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                  background-color: #f9fafb;
                  color: #374151;
                  margin: 0;
                  padding: 40px 20px;
                  text-align: center;
                }
                .container {
                  max-width: 400px;
                  margin: 0 auto;
                }
                h1 {
                  font-size: 1.5rem;
                  margin-bottom: 0.5rem;
                }
                p {
                  color: #6b7280;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>404 Not Found</h1>
                <p>The requested resource was not found.</p>
              </div>
            </body>
          </html>
        HTML
      end
    end
  end
end
