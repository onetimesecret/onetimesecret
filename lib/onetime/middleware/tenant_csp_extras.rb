# lib/onetime/middleware/tenant_csp_extras.rb
#
# frozen_string_literal: true

require 'otto/env_keys'

module Onetime
  module Middleware
    # Widens the CSP form-action directive with the resolved tenant's SSO IdP
    # origin, per request (#4173).
    #
    # The boot-time derivation (AuthConfig#sso_form_action_origins, applied in
    # Core::Application#build_router) can only see platform/env providers.
    # Tenant SSO issuers live in per-domain CustomDomain::SsoConfig records,
    # so on a custom domain the SSO form POST's 302 to the IdP was blocked by
    # `form-action` — silently, in the browser, with no server-side error.
    # This middleware resolves the tenant's IdP origin on the way IN and
    # writes it to otto's request-scoped CSP extras channel
    # (env['otto.csp.extra_directives'], delano/otto#243). Otto sanitizes the
    # tokens (origins-only grammar, additive-only, refused directives dropped)
    # at policy-build time, when Core::Middleware::RequestSetup's
    # finalize_response hands the env to Otto::Security::CSP::Writer.apply.
    #
    # Host resolution: the answer comes from env['onetime.display_domain'],
    # never Rack::Request#host. As HttpOriginOptions documents (#4170), a
    # proxy tier may rewrite Host to the canonical origin and forward the true
    # public host in another header; DetectHost + DomainStrategy already
    # resolved and validated that, publishing the result as display_domain —
    # reading Host here would widen the wrong host's policy.
    #
    # Gate: runs only when env['onetime.domain_strategy'] == :custom.
    # Canonical/subdomain hosts have no tenant SsoConfig; :invalid and nil are
    # not operator hosts, and :invalid is also DomainStrategy's answer when
    # its own datastore read raised (ADR-024 caveat — see
    # Core::Controllers::Base#custom_domain_request?). For a security-header
    # WIDENING, fail-closed = emit nothing = current behavior.
    #
    # Failure direction: any datastore error degrades to "no widening". This
    # is deliberately the OPPOSITE choice from the #4157 signin gates, which
    # prefer raising over misreading a failed policy read as "no config" —
    # there, a misread flips an access-control decision; here, the only
    # consequence of emitting nothing is the pre-#4173 behavior (the SSO
    # redirect stays blocked until the blip passes), which is safe.
    class TenantCspExtras
      def initialize(app)
        @app = app
      end

      def call(env)
        apply_tenant_extras(env) if env['onetime.domain_strategy'] == :custom
        @app.call(env)
      end

      private

      def apply_tenant_extras(env)
        origin = resolve_tenant_idp_origin(env)
        return if origin.nil?

        merge_form_action_extra(env, origin)
      rescue StandardError => ex
        OT.lw '[TenantCspExtras] skipping CSP widening for ' \
              "#{env['onetime.display_domain'].inspect}: #{ex.class}: #{ex.message}"
      end

      # The tenant's IdP origin, or nil when the domain has no available
      # tenant SSO. Availability is SsoConfig.tenant_sso_available_for? — the
      # SAME ladder ConfigSerializer#resolve_tenant_sso_config uses to decide
      # whether the page renders the SSO button, so the CSP stays in lockstep
      # with the affordance. The already-loaded record is handed to the
      # predicate via its sso_config: pass-through (single-read contract: the
      # verdict and the record whose issuer we emit are the same object).
      # Platform provider state (sso_enabled?, env credentials) is
      # deliberately NOT consulted: tenant SSO stands on its own.
      def resolve_tenant_idp_origin(env)
        display_domain = env['onetime.display_domain'].to_s
        return nil if display_domain.empty?

        custom_domain = Onetime::CustomDomain.load_by_display_domain(display_domain)
        return nil if custom_domain.nil?

        domain_id = custom_domain.identifier
        config    = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
        return nil if config.nil?
        return nil unless Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(
          domain_id, sso_config: config
        )

        # Mandatory funnel: origin_from_url inside — strips path, http(s)
        # only, rejects CSP-hostile hosts, nil on garbage (issuer is
        # tenant-supplied and therefore attacker-influenced).
        Onetime.auth_config.tenant_idp_origin(config)
      end

      # Merge (never clobber) the origin into the request-scoped extras hash.
      # Otto re-sanitizes everything at policy build, so an existing entry
      # written by another layer is preserved verbatim.
      def merge_form_action_extra(env, origin)
        existing = env[Otto::EnvKeys::CSP::EXTRA_DIRECTIVES]
        extras   = existing.is_a?(Hash) ? existing.dup : {}

        extras['form-action']                     = (Array(extras['form-action']) + [origin]).uniq
        env[Otto::EnvKeys::CSP::EXTRA_DIRECTIVES] = extras
      end
    end
  end
end
