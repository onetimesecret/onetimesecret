# lib/onetime/middleware/permissions_policy.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # PermissionsPolicy - emits the Permissions-Policy HTTP response header.
    #
    # Before the 2026-08-02 security audit (finding M-3) this policy shipped
    # only as a `<meta http-equiv="Permissions-Policy">` tag in head-base.rue.
    # Meta tags are weaker than real response headers: they can be displaced by
    # injected markup, are ignored for non-HTML resources, and `Permissions-
    # Policy` is not even a browser-recognized http-equiv value. This
    # middleware emits the same policy as an HTTP header on every response.
    #
    # The default policy disables the powerful features the app never uses
    # (geolocation, microphone, camera) for this origin and all embedded
    # content. Mirrors the meta tag in
    # apps/web/core/templates/partials/head-base.rue — keep the two in sync.
    #
    # Follows the Rack::Protection response-header convention (see
    # Rack::Protection::XSSHeader): set after calling downstream, and only
    # when no downstream layer already emitted the header (`||=`), so a route
    # can widen/narrow the policy without being clobbered.
    #
    # Enabled via site.middleware.permissions_policy
    # (ENV: MIDDLEWARE_PERMISSIONS_POLICY, default: true) — wired up in
    # Onetime::Middleware::Security like every other protection toggle.
    class PermissionsPolicy
      DEFAULT_POLICY = 'geolocation=(), microphone=(), camera=()'

      def initialize(app, options = {})
        @app    = app
        @policy = (options[:policy] || DEFAULT_POLICY).to_s
      end

      def call(env)
        status, headers, body           = @app.call(env)
        headers['permissions-policy'] ||= @policy unless @policy.empty?
        [status, headers, body]
      end
    end
  end
end
