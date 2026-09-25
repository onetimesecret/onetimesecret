# lib/onetime/middleware/http_origin_options.rb
#
# frozen_string_literal: true

require_relative '../tenant_sso_resolution'

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
      # SAML (#4450) IS THE SECOND SUCH PROVIDER. The HTTP-POST binding
      # delivers the SAMLResponse as a cross-site POST from the origin of the
      # IdP's SSO service URL — which is what the SAML definition's
      # :idp_origin_from names (not the EntityID, an opaque name that is often
      # on another host). Its CSRF control is not `state` but the one-shot
      # InResponseTo binding in OmniAuth::Strategies::RequestBoundSAML: a
      # response is refused unless this session holds the pending AuthnRequest
      # id it answers. This method covers PLATFORM providers only: a TENANT's
      # SAML IdP origin lives in a per-domain record, is unknown at boot, and
      # is not in AuthConfig#sso_idp_origins — .sso_callback_from_tenant_idp?
      # below is its counterpart.
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
        origin = sso_callback_post_origin(env)
        return false if origin.nil?

        auth_config = Onetime.auth_config
        return false unless auth_config.respond_to?(:sso_idp_origins)

        auth_config.sso_idp_origins.include?(origin)
      rescue StandardError => ex
        # A middleware that raises here would 500 every SSO callback. Denying
        # is the safe answer: HttpOrigin's own check still runs.
        OT.lw "[http_origin] SSO callback origin check failed: #{ex.class}: #{ex.message}"
        false
      end

      # Is this a form_post SSO callback arriving from the IdP that the
      # request's OWN custom domain configured (#4450)?
      #
      # The tenant half of .sso_callback_from_configured_idp?. A tenant's SAML
      # IdP posts the SAMLResponse to https://<custom domain>/auth/sso/<route>/callback
      # with `Origin: <the IdP's SSO service origin>`; without this the POST
      # is denied with 403 before OmniAuth runs, and tenant SAML can start a
      # login but never finish one.
      #
      # The default is the CSP form-action origin; SAML tenants may add
      # explicit callback-only origins through their authorized config API.
      # Both default-origin consumers ask the same questions of the same objects:
      # Onetime::TenantSsoResolution (which record, if any, is this host's
      # AVAILABLE tenant SSO config — the ladder that also decides whether the
      # SSO button renders) and AuthConfig#tenant_idp_origin (that record's IdP
      # origin, through the origin_from_url funnel).
      # Onetime::Middleware::TenantCspExtras admits the result into
      # form-action; this admits it as a callback Origin. Additional callback
      # origins never enter CSP form-action or the global platform set.
      #
      # SCOPED TO THE REQUEST'S DOMAIN, not to "any tenant's IdP": the
      # resolution is keyed on env['onetime.display_domain'] (DetectHost +
      # DomainStrategy; never the raw Host header), so tenant A's IdP origin
      # is admitted on tenant A's host only. SAML also requires its resolved
      # callback route; exceptions do not apply to other provider routes.
      #
      # Same parity argument and the same residual control as the platform
      # method: a matching Origin proves which document the POST came from,
      # and the callback must still answer a pending AuthnRequest id (SAML) or
      # `state` (OAuth) held by THIS session.
      #
      # Fails closed on every uncertainty: a non-POST method, any path but a
      # callback, a blank Origin, no display_domain, a canonical host, a
      # domain without AVAILABLE tenant SSO, an unreadable or invalid source
      # URL, a datastore error.
      #
      # @param env [Hash] Rack environment
      # @return [Boolean]
      def self.sso_callback_from_tenant_idp?(env)
        origin = sso_callback_post_origin(env)
        return false if origin.nil?
        return false if env['onetime.display_domain'].to_s.empty?

        auth_config = Onetime.auth_config
        return false unless auth_config.respond_to?(:tenant_idp_origin)

        sso_config = Onetime::TenantSsoResolution.for(env).sso_config
        return false if sso_config.nil?

        if sso_config.provider_type == 'saml'
          return false unless Rack::Request.new(env).path == "/auth/sso/#{sso_config.platform_route_name}/callback"

          # A separate POST-only policy; never add these origins to global
          # HttpOrigin or CSP allowances. An unreadable policy fails closed.
          return true if sso_config.callback_origins.include?(origin)
        end

        tenant_origin = auth_config.tenant_idp_origin(sso_config)
        !tenant_origin.nil? && tenant_origin == origin
      rescue StandardError => ex
        # Includes Redis::BaseError from the SsoConfig read. Denying is the
        # safe answer: HttpOrigin's own check still runs.
        OT.lw "[http_origin] tenant SSO callback origin check failed: #{ex.class}: #{ex.message}"
        false
      end

      # The Origin of a POST to an OmniAuth callback path, or nil when the
      # request is anything else. The shared precondition of both SSO
      # allowances: POST-only, callback-path-only, Origin present.
      #
      # @param env [Hash] Rack environment
      # @return [String, nil]
      def self.sso_callback_post_origin(env)
        return nil unless env['REQUEST_METHOD'] == 'POST'

        origin = env['HTTP_ORIGIN'].to_s
        return nil if origin.empty?

        # Rack::Request#path is SCRIPT_NAME + PATH_INFO, so this matches the
        # externally visible path even though the middleware runs inside the
        # auth app's mount — the same idiom the AuthenticityToken allow_if uses.
        return nil unless Rack::Request.new(env).path.match?(SSO_CALLBACK_PATH)

        origin
      end
      private_class_method :sso_callback_post_origin

      # Accept an Origin that matches the host the application already
      # resolved for this request. The scheme is hardcoded https: custom
      # domains are only served over TLS, and a laxer scheme would let a
      # network attacker on a plaintext leg mint a matching Origin.
      ALLOW_IF = ->(env) do
        next true if HttpOriginOptions.sso_callback_from_configured_idp?(env)
        next true if HttpOriginOptions.sso_callback_from_tenant_idp?(env)

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
