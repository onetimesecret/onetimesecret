# lib/onetime/security/csp.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # Single source of truth for the hardened, nonce-based Content-Security-Policy
    # directive list shared by every surface that emits CSP.
    #
    # Layer-agnostic: no Rack/Otto dependency. It returns a policy STRING from a
    # per-request nonce so callers (the V1 API in
    # apps/api/v1/controllers/helpers.rb#add_response_headers and the Core web app
    # in apps/web/core/middleware/request_setup.rb) cannot drift apart. The drift
    # between those two surfaces is precisely what previously left the user-facing
    # HTML pages with no CSP at all.
    #
    # Security properties (must hold for BOTH branches):
    # - script-src is NONCE-ONLY: it omits 'unsafe-inline' so a CSP Level 1 agent
    #   can't bypass the nonce.
    # - style-src KEEPS 'unsafe-inline' (intentional; required by Vite's dynamic
    #   style injection).
    # - connect-src is the only directive that differs dev vs prod (HMR needs the
    #   permissive websocket/http set in development).
    module Csp
      extend self

      # Build the CSP policy string for a single response.
      #
      # @param nonce [String] the per-request nonce (env['onetime.nonce']).
      # @param development [Boolean] truthy when running in development mode
      #   (OT.conf.dig('development','enabled')); selects the permissive
      #   connect-src needed for hot module replacement.
      # @param report_uri [String, nil] OPTIONAL path/URL to a CSP violation
      #   report receiver. When provided, a "report-uri <path>;" directive (and a
      #   "report-to csp-endpoint;" directive for the modern Reporting API) is
      #   appended so the browser knows where to POST violation reports. When nil
      #   (the default), NO reporting directive is emitted and the output is
      #   byte-identical to the historical policy — see
      #   spec/unit/api/v1/csp_header_spec.rb.
      # @return [String] the full policy string, directives space-joined in a
      #   stable order. Byte-identical to the policy previously inlined in the V1
      #   API helper when report_uri is omitted.
      def policy(nonce:, development:, report_uri: nil)
        directives =
          if development
            [
              "default-src 'none';",                       # Restrict to same origin by default
              "script-src 'nonce-#{nonce}';",              # Nonce-only: omit 'unsafe-inline' so CSP Level 1 agents can't bypass the nonce
              "style-src 'self' 'unsafe-inline';",         # Enable Vite's dynamic style injection
              "connect-src 'self' ws: wss: http: https:;", # Allow WebSocket connections for hot module replacement
              "img-src 'self' data:;",                     # Allow images from same origin only
              "font-src 'self';",                          # Allow fonts from same origin only
              "object-src 'none';",                        # Block <object>, <embed>, and <applet> elements
              "base-uri 'self';",                          # Restrict <base> tag targets to same origin
              "form-action 'self';",                       # Restrict form submissions to same origin
              "frame-ancestors 'none';",                   # Prevent site from being embedded in frames
              "manifest-src 'self';",
              # "require-trusted-types-for 'script';",
              "worker-src 'self';",                        # Allow Workers from same origin only
            ]
          else
            [
              "default-src 'none';",
              "script-src 'nonce-#{nonce}';",              # Nonce-only: omit 'unsafe-inline' so CSP Level 1 agents can't bypass the nonce
              "style-src 'self' 'unsafe-inline';",
              "connect-src 'self' wss: https:;",           # Only HTTPS and secure WebSockets
              "img-src 'self' data:;",
              "font-src 'self';",
              "object-src 'none';",
              "base-uri 'self';",
              "form-action 'self';",
              "frame-ancestors 'none';",
              "manifest-src 'self';",
              # "require-trusted-types-for 'script';",
              "worker-src 'self';",
            ]
          end

        # OPTIONAL reporting directives. Appended only when a report_uri is
        # supplied so the default (no report_uri) output stays byte-identical.
        # report-uri is the legacy directive (widely supported); report-to is the
        # modern Reporting API directive whose endpoint name ('csp-endpoint') is
        # defined by a separate Reporting-Endpoints response header emitted at the
        # web layer.
        unless report_uri.nil? || report_uri.to_s.empty?
          directives << "report-uri #{report_uri};"
          directives << 'report-to csp-endpoint;'
        end

        directives.join(' ')
      end
    end
  end
end
