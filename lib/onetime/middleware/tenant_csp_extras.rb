# lib/onetime/middleware/tenant_csp_extras.rb
#
# frozen_string_literal: true

require 'otto/env_keys'

require_relative '../tenant_sso_resolution'

# Fail fast on an otto without the request-scoped CSP extras channel
# (delano/otto#243, targeting otto 2.9). Released otto 2.8.1 ships
# otto/env_keys WITHOUT the CSP submodule and Writer.apply without env:, so if
# the Gemfile ever resolves it (e.g. a revert to `~> 2.8` after the feature
# branch is deleted), the failure would otherwise surface as a NameError
# swallowed per-request by the rescue below (silent feature death) plus an
# `ArgumentError: unknown keyword: :env` 500ing every HTML response. A boot
# failure with a named cause beats a silent no-op.
unless defined?(Otto::EnvKeys::CSP::EXTRA_DIRECTIVES)
  otto_version = defined?(Otto::VERSION) ? Otto::VERSION : '(unknown)'
  raise LoadError,
    'otto >= 2.9 with CSP request extras required; resolved otto ' \
    "#{otto_version} lacks Otto::EnvKeys::CSP::EXTRA_DIRECTIVES — " \
    'check the Gemfile otto entry'
end

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
    # This middleware runs on the way OUT: after the downstream app has
    # produced its response, and only when that response would actually carry
    # a CSP (CSP enabled, HTML media type), it resolves the tenant's IdP
    # origin and writes it to otto's request-scoped CSP extras channel
    # (env['otto.csp.extra_directives'], delano/otto#243). Otto sanitizes the
    # tokens (origins-only grammar, additive-only, refused directives dropped)
    # at policy-build time, when Core::Middleware::RequestSetup's
    # finalize_response — the OUTER layer, so it still sees this write —
    # hands the env to Otto::Security::CSP::Writer.apply. Resolving on the
    # way out keeps static assets, JSON, 404s, and health checks (and every
    # request when CSP is disabled) from paying datastore round-trips whose
    # result otto would discard anyway (Writer skips non-HTML before reading
    # extras).
    #
    # This CSP is emitted only by the Core-rendered pages. The API/auth apps
    # emit their own CSP (Rack::Protection::ContentSecurityPolicy via the
    # authenticated_web profile: `default-src 'self'`) but no form-action
    # directive — and form-action has no default-src fallback — so the
    # enforcing document for the SSO form is the Core-rendered page this
    # middleware wraps.
    #
    # Host resolution: the answer comes from env['onetime.display_domain'],
    # never Rack::Request#host. As HttpOriginOptions documents (#4170), a
    # proxy tier may rewrite Host to the canonical origin and forward the true
    # public host in another header; DetectHost + DomainStrategy already
    # resolved and validated that, publishing the result as display_domain —
    # reading Host here would widen the wrong host's policy.
    #
    # Deliberately NOT gated on env['onetime.domain_strategy']: the SSO
    # button's serializer (ConfigSerializer#resolve_tenant_sso_config) keys
    # purely on display_domain with no strategy check, and DomainStrategy
    # classifies a real custom domain :invalid when its own datastore read
    # blips while display_domain survives — a strategy gate here would then
    # render the button but skip the widening, recreating the exact #4173
    # symptom. Keying both surfaces on display_domain alone keeps the CSP in
    # lockstep with the affordance.
    #
    # Lockstep is now structural, not parallel: the tenant SSO answer comes
    # from Onetime::TenantSsoResolution.for(env) — the SAME request-scoped
    # object the page's serializers resolved through while rendering. On a
    # normal page render this middleware therefore performs NO datastore work
    # at all (the resolution is already memoized on the env), and the record
    # whose issuer widens form-action is by construction the record that
    # decided whether the button renders. Only an HTML response produced
    # without the serializers (a static error page) pays the lookup here, and
    # then a canonical host stops at the domain-index miss.
    #
    # Failure direction: any datastore error degrades to "no widening". This
    # is deliberately the OPPOSITE choice from the #4157 signin gates, which
    # prefer raising over misreading a failed policy read as "no config" —
    # there, a misread flips an access-control decision; here, the only
    # consequence of emitting nothing is the pre-#4173 behavior (the SSO
    # redirect stays blocked until the blip passes), which is safe.
    class TenantCspExtras
      # Upper bound on the tenant-supplied issuer text reproduced in a log
      # line. Long enough to identify the offending record, short enough that
      # a hostile value cannot flood the log.
      ISSUER_LOG_LIMIT = 100

      def initialize(app)
        @app                            = app
        @warned_rejected_origin_domains = Set.new
        @warning_lock                   = Mutex.new
      end

      def call(env)
        status, headers, body = @app.call(env)
        apply_tenant_extras(env, headers)

        [status, headers, body]
      end

      private

      # Guards run cheapest-first, and all of them before any datastore read:
      # the app-side CSP toggle (the same site.security.csp.enabled gate
      # RequestSetup#emit_csp_header applies), then the response media type,
      # then a present display_domain.
      def apply_tenant_extras(env, headers)
        return unless OT.conf.dig('site', 'security', 'csp', 'enabled')
        return unless html_response?(headers)

        display_domain = env['onetime.display_domain'].to_s
        return if display_domain.empty?

        origin = resolve_tenant_idp_origin(env, display_domain)
        return if origin.nil?

        merge_form_action_extra(env, origin)
      rescue StandardError => ex
        # Narrow by construction: the resolution's domain read answers
        # nil-or-sentinel rather than raising (TenantSsoResolution swallows
        # the datastore error the way CustomDomain.load_by_display_domain
        # does, per the #4157 convention notes in Core::Controllers::Base),
        # so this rescue only catches failures from the SsoConfig/
        # availability reads and the origin derivation. Either way a failed
        # domain read degrades silently to no-widening — the accepted
        # fail-closed direction for a header widening.
        OT.lw '[TenantCspExtras] skipping CSP widening for ' \
              "#{env['onetime.display_domain'].inspect}: #{ex.class}: #{ex.message}"
      end

      # Whether the response's media type is HTML, matching how otto's Writer
      # decides emission (leading token before ';', case-insensitive,
      # 'text/html' exactly), with one deliberate difference: an ABSENT
      # Content-Type counts as HTML here. RequestSetup (the outer layer)
      # defaults a missing Content-Type to text/html in finalize_response
      # BEFORE the Writer sees it, so a header-less response will be emitted
      # as HTML with a CSP — skipping the widening for it would reopen the
      # lockstep gap this middleware exists to close.
      def html_response?(headers)
        content_type = headers.find { |key, _value| key.to_s.casecmp?('content-type') }&.last
        return true if content_type.nil?

        content_type.to_s.split(';', 2).first.to_s.strip.casecmp?('text/html')
      end

      # The tenant's IdP origin, or nil when the domain has no available
      # tenant SSO.
      #
      # The ladder itself (domain lookup → SsoConfig → the
      # SsoConfig.tenant_sso_available_for? availability check, with the
      # loaded record handed to the predicate) lives in
      # Onetime::TenantSsoResolution, shared with the serializers that decide
      # whether the page renders the SSO button — so this cannot answer for a
      # different record than the button was rendered from. Platform provider
      # state (sso_enabled?, env credentials) is deliberately NOT consulted:
      # tenant SSO stands on its own.
      def resolve_tenant_idp_origin(env, display_domain)
        config = Onetime::TenantSsoResolution.for(env).sso_config
        return nil if config.nil?

        # Mandatory funnel: origin_from_url inside — strips path, http(s)
        # only, rejects CSP-hostile hosts, nil on garbage (issuer is
        # tenant-supplied and therefore attacker-influenced).
        origin = Onetime.auth_config.tenant_idp_origin(config)
        warn_rejected_origin_source(display_domain, config) if origin.nil?

        origin
      end

      # One warning for the "configured, believed working, silently doing
      # nothing" state: the availability ladder said yes (so the page IS
      # rendering the tenant SSO button) and the tenant supplied a non-blank
      # origin source, yet the funnel rejected it. Without this line the only
      # symptom is a blocked redirect in the visitor's browser console — the
      # exact #4173 failure mode, now with the SSO button on screen. Every
      # other nil path is a NORMAL state (no custom domain, no SsoConfig,
      # availability false, blank issuer) and stays silent.
      #
      # Purely observational: nil still means "no widening". The fail-closed
      # direction is deliberate (see the class comment) and a log line must
      # not move it.
      #
      # Scoped by AuthConfig#tenant_origin_source on purpose — the SAME
      # dispatch #tenant_idp_origin itself runs, so this cannot drift out of
      # step with which types actually read the tenant issuer. For the other
      # provider types the origin comes from the static registry definition,
      # not from tenant data, so a nil there means route-map/registry drift —
      # a deploy-side bug an operator cannot fix by editing the tenant record.
      # Reporting it as a bad tenant issuer would name the wrong cause (and
      # the record's issuer field may be stale-but-unused for those types).
      #
      # Warn once per normalized custom domain for this middleware process.
      # It retains one entry per encountered custom domain rather than one per
      # request, and the mutex keeps concurrent HTML requests from logging the
      # same misconfiguration more than once.
      def warn_rejected_origin_source(display_domain, config)
        source = Onetime.auth_config.tenant_origin_source(config)
        return if source.nil? || source.empty?
        return unless first_rejected_origin_warning_for?(display_domain)

        OT.lw '[TenantCspExtras] tenant SSO is available but its IdP origin failed ' \
              "validation for #{display_domain.inspect} " \
              "(provider_type=#{config.provider_type.to_s.inspect}, " \
              "issuer=#{truncate_for_log(source).inspect}); form-action not widened"
      end

      def first_rejected_origin_warning_for?(display_domain)
        @warning_lock.synchronize do
          @warned_rejected_origin_domains.add?(display_domain.downcase)
        end
      end

      # Bounded, escaped rendering of an attacker-influenced value. The
      # caller passes the result through #inspect, which escapes newlines and
      # control characters — that is what prevents a crafted issuer from
      # forging additional log lines.
      def truncate_for_log(value)
        return value if value.length <= ISSUER_LOG_LIMIT

        "#{value[0, ISSUER_LOG_LIMIT]}..."
      end

      # Merge (never clobber) the origin into the request-scoped extras hash.
      #
      # Pre-existing entries are first normalized with otto's own rules
      # (Otto::Security::CSP::RequestExtras): directive keys via
      # to_s.strip.downcase.tr('_', '-') — otherwise a 'form_action' /
      # :form_action / 'Form-Action' spelling would only collide with our
      # 'form-action' inside otto, where plain hash assignment lets one side
      # silently win — and String values split on whitespace, because otto
      # reads a String value as a whitespace-separated source list;
      # Array('https://a https://b') would wrap it as ONE token that otto's
      # FORBIDDEN_CHARS (whitespace) check then drops wholesale, vanishing
      # the other layer's origins. Keys that collapse under normalization
      # have their token lists concatenated. Otto re-sanitizes every
      # surviving token at policy build.
      def merge_form_action_extra(env, origin)
        extras = normalize_extras(env[Otto::EnvKeys::CSP::EXTRA_DIRECTIVES])

        extras['form-action']                     = (extras.fetch('form-action', []) + [origin]).uniq
        env[Otto::EnvKeys::CSP::EXTRA_DIRECTIVES] = extras
      end

      # A fresh hash with otto-normalized keys and Array-of-tokens values.
      # Never aliases the caller's hash or its nested arrays, so the original
      # extras value is left untouched.
      def normalize_extras(existing)
        return {} unless existing.is_a?(Hash)

        existing.each_with_object({}) do |(key, value), acc|
          name      = key.to_s.strip.downcase.tr('_', '-')
          tokens    = value.is_a?(String) ? value.split : Array(value)
          acc[name] = acc.fetch(name, []) + tokens
        end
      end
    end
  end
end
