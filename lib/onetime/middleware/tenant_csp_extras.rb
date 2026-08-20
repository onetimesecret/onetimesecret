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
    # a CSP (CSP enabled, document status, HTML media type), it resolves the
    # tenant's IdP origin and writes it to otto's request-scoped CSP extras
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
    # redirect stays blocked until the blip passes), which is safe. That
    # tolerance covers datastore errors ONLY: any other exception on this
    # path is a code defect whose sole symptom would be the #4173 symptom
    # itself, so it is logged at error level (see #apply_tenant_extras).
    class TenantCspExtras
      # Upper bound on the tenant-supplied issuer text reproduced in a log
      # line. Long enough to identify the offending record, short enough that
      # a hostile value cannot flood the log.
      ISSUER_LOG_LIMIT = 100

      # Bodyless 2xx statuses to skip; document_status? also skips 1xx and
      # every 3xx via range checks. No browser parses any of them as a
      # document, so no CSP the widening could belong to is ever enforced.
      # 304 is the volume case — Rack::Files answers [304, {}, []]
      # for each revalidated asset and StaticFiles is mounted INSIDE this
      # middleware, so without this guard a custom-domain page reload paid the
      # tenant resolution ladder once per asset. 4xx/5xx are NOT skipped: an
      # error page is a rendered document.
      NON_DOCUMENT_STATUSES = [204, 205].freeze

      def initialize(app)
        @app                            = app
        @warned_rejected_origin_domains = Set.new
        @warning_lock                   = Mutex.new
      end

      def call(env)
        status, headers, body = @app.call(env)
        apply_tenant_extras(env, status, headers)

        [status, headers, body]
      end

      private

      # Guards run cheapest-first, and all of them before any datastore read:
      # the app-side CSP toggle (the same site.security.csp.enabled gate
      # RequestSetup#emit_csp_header applies), then the response status, then
      # the response media type, then a present display_domain.
      def apply_tenant_extras(env, status, headers)
        return unless OT.conf.dig('site', 'security', 'csp', 'enabled')
        return unless document_status?(status)
        return unless html_response?(env, headers)

        display_domain = env['onetime.display_domain'].to_s
        return if display_domain.empty?

        origin = resolve_tenant_idp_origin(env, display_domain)
        return if origin.nil?

        merge_form_action_extra(env, origin)
      rescue Redis::BaseError => ex
        # The one EXPECTED degraded mode: a datastore blip on the SsoConfig/
        # availability reads (the resolution answers its own domain read as
        # DOMAIN_READ_FAILED rather than raising). Degrade to no-widening —
        # the pre-#4173 behavior, safe by the fail-open direction argued in
        # the class comment — and log at warn, not error.
        OT.lw '[TenantCspExtras] datastore error, skipping CSP widening for ' \
              "#{env['onetime.display_domain'].inspect}: #{ex.class}: #{ex.message}"
      rescue StandardError => ex
        # Anything else is a code defect on this path, and its only other
        # symptom is the #4173 symptom itself: a redirect the browser blocks,
        # with no server-side error. The response must still not 500 over a
        # CSP extra, so it is swallowed — but LOUDLY, at error level with the
        # exception attached, so it alerts instead of becoming a permanent
        # unmonitored regression.
        OT.le '[TenantCspExtras] unexpected error, skipping CSP widening for ' \
              "#{env['onetime.display_domain'].inspect}: #{ex.class}: #{ex.message}",
          exception: ex
      end

      # Whether the status can carry a document a CSP would govern. Keeps the
      # resolution ladder off revalidation and redirect traffic.
      def document_status?(status)
        code = status.to_i
        return false if code < 200
        return false if (300..399).cover?(code)

        !NON_DOCUMENT_STATUSES.include?(code)
      end

      # Whether the response's media type is HTML, matching how otto's Writer
      # decides emission (leading token before ';', case-insensitive,
      # 'text/html' exactly).
      #
      # An ABSENT Content-Type is the ambiguous case. RequestSetup (the outer
      # layer) defaults a missing Content-Type to text/html in
      # finalize_response BEFORE the Writer sees it, so a header-less response
      # CAN still be emitted as HTML with a CSP — but treating every such
      # response as HTML made bodyless replies pay the full tenant ladder.
      # Split by cost: when the app already memoized a resolution on the env
      # (a real render went through the serializers), reusing it is free, so
      # stay in lockstep; otherwise require an explicit text/html.
      def html_response?(env, headers)
        content_type = headers.find { |key, _value| key.to_s.casecmp?('content-type') }&.last
        return env.key?(Onetime::TenantSsoResolution::ENV_KEY) if content_type.nil?

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

      # Add the origin to the request-scoped extras hash without clobbering
      # what another layer wrote.
      #
      # Normalization is otto's job, not ours:
      # Otto::Security::CSP::RequestExtras.from_env normalizes directive keys
      # (so a 'form_action' / :form_action / 'Form-Action' entry from another
      # layer is recognized), UNIONS keys that collapse to the same directive
      # rather than letting one win, and re-sanitizes every token at policy
      # build. A non-Hash value is dropped there wholesale, so replacing one
      # here costs nothing. The only step that cannot wait for otto is
      # splitting a String value of OUR key: otto reads a String as a
      # whitespace-separated source list but takes an Array element-wise, so
      # wrapping 'https://a https://b' into one array element would turn it
      # into a single whitespace-bearing token otto then drops.
      def merge_form_action_extra(env, origin)
        existing = env[Otto::EnvKeys::CSP::EXTRA_DIRECTIVES]
        extras   = existing.is_a?(Hash) ? existing.dup : {}
        current  = extras['form-action']
        tokens   = current.is_a?(String) ? current.split : Array(current)

        extras['form-action']                     = (tokens + [origin]).uniq
        env[Otto::EnvKeys::CSP::EXTRA_DIRECTIVES] = extras
      end
    end
  end
end
