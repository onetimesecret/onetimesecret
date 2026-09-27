# lib/onetime/middleware/http_origin_options.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # Shared options for Rack::Protection::HttpOrigin.
    #
    # HttpOrigin resolves the request host via Rack::Request#host, which reads
    # the Host header (or X-Forwarded-Host when present). Behind a proxy tier
    # that rewrites Host to the canonical origin and forwards the true public
    # host in another header (Apx-Incoming-Host, X-Original-Host, Forwarded),
    # that answer is wrong — which is exactly why the app mounts
    # Rack::DetectHost and DomainStrategy, whose validated result is published
    # as env['onetime.display_domain'].
    #
    # Without this allow_if, every unsafe-method request from a custom domain
    # is rejected with 403 before reaching a route, because the Origin header
    # (custom domain) never byte-matches the Host header (canonical origin).
    #
    # The comparison here is exact and https-only, against a host that
    # DetectHost accepts from forwarded headers only behind trusted
    # infrastructure and DomainStrategy classifies against registered custom
    # domains. A forged Origin cannot match because an attacker cannot move
    # display_domain. An absent or empty display_domain fails closed: allow_if
    # returns false and HttpOrigin's own Origin-vs-Host check decides.
    #
    # Consumed by both HttpOrigin mounts — Onetime::Middleware::Security
    # (toggle: site.middleware.http_origin) and the auth app's middleware
    # profile (apps/web/auth/application.rb) — so their behavior cannot drift.
    module HttpOriginOptions
      # An OmniAuth CALLBACK path, and nothing else under /auth/sso/.
      #
      # Anchored and callback-only ON PURPOSE. The REQUEST phase
      # (POST /auth/sso/:provider) is a genuine CSRF target — it starts a
      # flow and, for Connect, mints the account-bound intent nonce that
      # authorizes binding an identity to the signed-in account (see
      # omniauth_request_validation_phase in
      # apps/web/auth/config/hooks/omniauth.rb). It keeps Origin protection.
      # Only the callback, whose CSRF control is the OAuth `state` parameter,
      # is exempt.
      SSO_CALLBACK_PATH = %r{\A/auth/sso/[^/]+/callback\z}

      # Is this a form_post SSO callback arriving from an IdP this deployment
      # actually configured?
      #
      # WHY THIS EXISTS (Sign in with Apple). Apple sets
      # response_mode=form_post whenever a scope is requested, so its callback
      # is a cross-site POST carrying `Origin: https://appleid.apple.com`.
      # Rack::Protection::HttpOrigin#accepts? then finds: not a safe method, an
      # Origin that is present, an Origin that is not base_url, and a
      # display_domain that can never equal an IdP host — so it denies with
      # 403 before OmniAuth (and before omniauth_request_validation_phase) ever
      # runs. Every provider before Apple had a GET callback, which `safe?`
      # short-circuits, so the gap only appears now.
      #
      # THIS IS PARITY, NOT A NEW HOLE. A GET callback bypasses HttpOrigin
      # entirely today via `safe?` — no Origin check at all, from any origin.
      # This grants a POST callback the same treatment and strictly less: the
      # Origin must exactly match one of the IdP origins this deployment has
      # configured (AuthConfig#sso_idp_origins — the same set CSP form-action
      # allows to receive the redirect). Unconfigured and unknown origins are
      # still denied on POST.
      #
      # The Origin header is set by the browser and cannot be forged by page
      # script, so a matching Origin means the POST really came from that IdP's
      # document. A non-browser client can send any Origin, but carries no
      # victim cookie — and the callback still has to present a `state` that
      # OmniAuth minted into this session, which is the control the app already
      # relies on for every other SSO route (see the CSRF bypass note in
      # hooks/omniauth.rb and the AuthenticityToken allow_if in registry.rb).
      #
      # Fails closed on every uncertainty: a non-POST method, any path but a
      # callback, a blank Origin, an unconfigured deployment, or an
      # auth_config that cannot answer.
      #
      # @param env [Hash] Rack environment
      # @return [Boolean]
      def self.sso_callback_from_configured_idp?(env)
        return false unless env['REQUEST_METHOD'] == 'POST'

        origin = env['HTTP_ORIGIN'].to_s
        return false if origin.empty?

        # Rack::Request#path is SCRIPT_NAME + PATH_INFO, so this matches the
        # externally visible path even though the middleware runs inside the
        # auth app's mount — the same idiom the AuthenticityToken allow_if uses.
        return false unless Rack::Request.new(env).path.match?(SSO_CALLBACK_PATH)

        auth_config = Onetime.auth_config
        return false unless auth_config.respond_to?(:sso_idp_origins)

        auth_config.sso_idp_origins.include?(origin)
      rescue StandardError => ex
        # A middleware that raises here would 500 every SSO callback. Denying
        # is the safe answer: HttpOrigin's own check still runs.
        OT.lw "[http_origin] SSO callback origin check failed: #{ex.class}: #{ex.message}"
        false
      end

      # Accept an Origin that matches the host the application already
      # resolved for this request. The scheme is hardcoded https: custom
      # domains are only served over TLS, and a laxer scheme would let a
      # network attacker on a plaintext leg mint a matching Origin.
      ALLOW_IF = ->(env) do
        next true if HttpOriginOptions.sso_callback_from_configured_idp?(env)

        display = env['onetime.display_domain'].to_s
        next false if display.empty?

        env['HTTP_ORIGIN'].to_s == "https://#{display}"
      end

      def self.options
        { allow_if: ALLOW_IF }
      end
    end
  end
end
