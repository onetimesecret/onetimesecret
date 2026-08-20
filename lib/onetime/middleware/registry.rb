# lib/onetime/middleware/registry.rb
#
# frozen_string_literal: true

#
# Central registry of security/middleware components.
#
# This is the single component table that middleware consumers draw from.
# It is consumed by Onetime::Middleware::Security (which mounts the nine
# config-toggled protections) and by the per-app middleware profiles
# (Onetime::Application::MiddlewareProfile), which replaced the ad-hoc
# environment-conditional `use` blocks (e.g. apps/web/auth/application.rb's
# former production-only stack).
#
# Each entry: display name => {
#   key:                Symbol   — operator config toggle under site.middleware
#   klass:              Class    — the Rack middleware class
#   options:            Hash     — (optional) keyword options for the middleware
#   warn_when_disabled: Boolean  — project guidance: log a warning when disabled
# }
#
# `key` is operator configuration (whether this deployment runs a component).
# `warn_when_disabled` is project-owner guidance (whether disabling it merits
# review). They intentionally remain separate so operator and owner choices can
# disagree visibly in the startup log.

require 'rack'
require 'rack/protection'
require 'rack/utf8_sanitizer'

require_relative 'http_origin_options'
require_relative 'instrumented_authenticity_token'
require_relative 'permissions_policy'
require_relative 'xss_header'

module Onetime
  module Middleware
    module Registry
      COMPONENTS = {
        # UTF-8 Sanitization: Ensures request parameters use valid UTF-8 encoding.
        'UTF8Sanitizer' => {
          key: :utf8_sanitizer,
          klass: Rack::UTF8Sanitizer,
          options: { sanitize_null_bytes: true },
          warn_when_disabled: true,
        },

        # CSRF Protection (Token-based): Validates 'shrimp' authenticity tokens.
        #
        # This middleware validates CSRF tokens for all state-changing requests (POST, PUT, etc.)
        # using Rack::Protection::AuthenticityToken. The raw token is stored in session[:csrf],
        # but forms submit a MASKED version (different each request) to mitigate BREACH attacks.
        #
        # Bypass rules:
        # - SSO routes (/auth/sso/*): Use OAuth 'state' parameter for CSRF protection
        # - API routes WITHOUT an authenticated session cookie: no ambient credential to
        #   forge, so no CSRF vector (Basic-Auth API-key clients, anonymous/programmatic
        #   callers, unauthenticated secret recipients, the /api/incoming/* inbound surface)
        # - Web/SPA + session-authenticated API routes: Must include X-CSRF-Token header
        #   (Axios interceptor) or 'shrimp' form param
        #
        # Note: API v1 has no session/cookie auth (Basic Auth or anonymous only), so v1
        # requests never carry an authenticated session and always bypass. API v2/v3
        # support session auth; a logged-in SPA user hitting those endpoints is required
        # to present a CSRF token (the allow_if lambda enforces this by checking for an
        # authenticated session cookie).
        #
        # See also: apps/web/auth/config/hooks/omniauth.rb for Rodauth-side bypass
        'AuthenticityToken' => {
          key: :authenticity_token,
          # Subclass of Rack::Protection::AuthenticityToken that stamps
          # env['onetime.csrf.rejected'] on rejection so CsrfResponseHeader can
          # distinguish a real CSRF 403 from an unrelated 403. See
          # InstrumentedAuthenticityToken for why the subclass (not an :instrumenter).
          klass: Onetime::Middleware::InstrumentedAuthenticityToken,
          options: {
            authenticity_param: 'shrimp',
            allow_if: ->(env) {
              req = Rack::Request.new(env)

              # SSO routes use OAuth state parameter for CSRF protection
              return true if req.path.start_with?('/auth/sso/')

              # Magic link routes: The email-auth token itself provides CSRF protection
              # - Token is cryptographically random, one-time use, and time-limited
              # - User arrives from external email client without existing session/CSRF token
              # - Similar to SSO: the authentication token validates the request
              return true if req.path == '/auth/email-login'

              # API routes: bypass CSRF ONLY when there is no ambient session cookie to
              # forge against. A CSRF attack rides the victim's session cookie, so the
              # discriminator MUST be the authenticated session — not merely the presence
              # of an Authorization header.
              #   - Basic Auth (API key): a stateless credential sent explicitly per
              #     request; no ambient cookie => no CSRF vector => bypass.
              #   - No authenticated session cookie (anonymous/programmatic clients, v1
              #     which has no session auth, unauthenticated secret recipients, and the
              #     entire /api/incoming/* inbound surface): nothing to forge => bypass.
              #   - Session-cookie-authenticated API request (logged-in SPA user): fall
              #     through and require a valid X-CSRF-Token. The SPA sends it on every
              #     request (axios interceptor), so this does not break the app; it only
              #     rejects a forged cross-site request that presents no token.
              if req.path.start_with?('/api/')
                return true if env['HTTP_AUTHORIZATION'].to_s.start_with?('Basic ')

                session = env['rack.session']
                return true unless session && session['authenticated'] == true
                # else: session-authenticated API request -> fall through, require token
              end

              # NOTE: Incoming secrets API is now at /api/incoming/* and covered by the /api/ check above.
              # The frontend page at /incoming uses GET requests which don't require CSRF protection.

              # Webhook endpoints use their own signature-based verification (e.g., Stripe-Signature header)
              # They're called server-to-server, not from browsers, so CSRF doesn't apply
              return true if req.path == '/billing/webhook'

              false
            },
          },
          warn_when_disabled: true,
        },

        # CSRF Protection (Origin-based): Validates Origin and Referer headers.
        #
        # The allow_if accepts an Origin matching env['onetime.display_domain'],
        # the host DetectHost/DomainStrategy already resolved for this request —
        # without it, custom-domain requests behind a Host-rewriting proxy are
        # rejected with 403. Shared with the auth app's mount via
        # HttpOriginOptions so the two cannot drift.
        'HttpOrigin' => {
          key: :http_origin,
          klass: Rack::Protection::HttpOrigin,
          options: Onetime::Middleware::HttpOriginOptions.options,
          warn_when_disabled: true,
        },

        # NOTE: Rack::Protection::EscapedParams is intentionally EXCLUDED.
        # It escapes all parameters uniformly, which would corrupt sensitive data
        # like passwords and secrets. OTS uses Onetime::Security::InputSanitizers
        # for field-aware sanitization instead.

        # XSS Header: Sets X-XSS-Protection to mitigate reflected XSS in older browsers.
        # Uses the Onetime subclass rather than Rack::Protection::XSSHeader
        # because the latter can only emit `1; mode=...`, which is an XS-Leaks
        # vector in the legacy browsers that still ship the XSS auditor
        # (see xss_header.rb). nosniff is the load-bearing half.
        'XSSHeader' => {
          key: :xss_header,
          klass: Onetime::Middleware::XSSHeader,
          warn_when_disabled: true,
        },

        # Referrer Policy: Emits Referrer-Policy: no-referrer on every response.
        # Secret links carry secret identifiers in the URL path, so ANY referrer
        # leakage is a disclosure vector (2026-08-02 audit, M-3.2). The meta tag
        # in head-base.rue mirrors this value; keep the two in sync.
        'ReferrerPolicy' => {
          key: :referrer_policy,
          klass: Rack::Protection::ReferrerPolicy,
          options: { referrer_policy: 'no-referrer' },
          warn_when_disabled: true,
        },

        # Permissions Policy: Emits Permissions-Policy disabling geolocation,
        # microphone and camera as a real response header (2026-08-02 audit,
        # M-3.3). Same policy as the head-base.rue meta tag.
        'PermissionsPolicy' => {
          key: :permissions_policy,
          klass: Onetime::Middleware::PermissionsPolicy,
          warn_when_disabled: true,
        },

        # Frame Options: Prevents clickjacking by restricting iframe embedding.
        'FrameOptions' => {
          key: :frame_options,
          klass: Rack::Protection::FrameOptions,
          warn_when_disabled: true,
        },

        # Path Traversal: Prevents directory traversal attacks in request paths.
        'PathTraversal' => {
          key: :path_traversal,
          klass: Rack::Protection::PathTraversal,
          warn_when_disabled: true,
        },

        # Cookie Tossing: Blocks session fixation via cookies set on subdomains.
        'CookieTossing' => {
          key: :cookie_tossing,
          klass: Rack::Protection::CookieTossing,
          warn_when_disabled: true,
        },

        # IP Spoofing: Detects and blocks IP spoofing attempts via header validation.
        'IPSpoofing' => {
          key: :ip_spoofing,
          klass: Rack::Protection::IPSpoofing,
          warn_when_disabled: true,
        },

        # HSTS: Forces HTTPS by setting the Strict-Transport-Security header.
        'StrictTransport' => {
          key: :strict_transport,
          klass: Rack::Protection::StrictTransport,
          warn_when_disabled: true,
        },

        # --------------------------------------------------------------------
        # Entries below are consumed by the :authenticated_web middleware
        # profile (lib/onetime/application/middleware_profile.rb), gated by
        # site.middleware.profiles.authenticated_web.<key> config with
        # defaults ON in every environment.
        # --------------------------------------------------------------------

        # Gzip response compression (not a protection; auth app profile stack).
        'Deflater' => {
          key: :deflater,
          klass: Rack::Deflater,
          warn_when_disabled: false,
        },

        # CSP: Sets a Content-Security-Policy header restricting resource origins.
        'ContentSecurityPolicy' => {
          key: :content_security_policy,
          klass: Rack::Protection::ContentSecurityPolicy,
          warn_when_disabled: false,
        },

        # Session Hijacking: Ties the session to stable client attributes.
        'SessionHijacking' => {
          key: :session_hijacking,
          klass: Rack::Protection::SessionHijacking,
          warn_when_disabled: false,
        },
      }.freeze

      # @return [Hash] the full ordered, frozen component table
      def self.components
        COMPONENTS
      end

      # @param name [String] component display name, e.g. 'HttpOrigin'
      # @return [Hash] the component entry
      # @raise [KeyError] if the name is not registered
      def self.fetch(name)
        COMPONENTS.fetch(name)
      end

      # @param key [Symbol, String] config toggle key, e.g. :frame_options
      # @return [Boolean] whether disabling this toggle warrants a warning
      def self.warn_when_disabled?(key)
        key = key.to_sym
        COMPONENTS.any? { |_name, cfg| cfg[:key] == key && cfg[:warn_when_disabled] }
      end
    end
  end
end
