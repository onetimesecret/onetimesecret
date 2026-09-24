# apps/web/auth/lib/public_host.rb
#
# frozen_string_literal: true

module Auth
  # The PUBLIC host for a request — the hostname the browser actually used —
  # and the absolute base URL built from it.
  #
  # Behind a Host-rewriting proxy (Approximated, and any origin-target
  # rewriter) the Rack authority is NOT what the visitor typed: the browser
  # asks for nz.example.com, the proxy forwards that in `Apx-Incoming-Host`
  # and rewrites `Host:` to the origin target. Anything derived from
  # `request.host` / `request.base_url` therefore names the wrong host —
  # tenant lookups miss (#4224), SSO redirect_uris are rejected as
  # unregistered, and transactional email links point at a host the recipient
  # never visited (#4221).
  #
  # `env['onetime.display_domain']` is the resolution: Rack::DetectHost picks
  # the forwarded host ONLY from trusted infrastructure and DomainStrategy
  # validates it, so it is also the SAFER key — Rack 3.2's `request.host`
  # prefers `X-Forwarded-Host`/`Forwarded` from ANY client, ungated by proxy
  # trust. Reading the raw header would reopen reset-password link poisoning.
  #
  # ## Host allowlisting — positive evidence required (finding G-01)
  #
  # Neither `display_domain` nor DetectHost's result is, on its own, proof
  # that the host is a tenant we actually serve. `DomainStrategy#call` writes
  # `display_domain` for ANY syntactically-valid host regardless of
  # classification (it pins it to the canonical host on some paths, and echoes
  # a detected host on others), and DetectHost only proves the host reached us
  # through trusted infrastructure — not that it belongs to a registered
  # customer. An unregistered, expired, or attacker-CNAMEd host can therefore
  # travel in these keys, and any URL built from it lands the recipient of a
  # genuine service email on an attacker origin — one click yields account
  # takeover, cross-tenant on the multi-tenant platform.
  #
  # So a candidate is accepted ONLY when it names a VERIFIED custom domain:
  # `Onetime::CustomDomain.from_display_domain(host)` resolves a record AND
  # that record's ownership is TXT-verified (`verified`). Mere registration is
  # not enough here — anyone can register a domain record they don't control,
  # and an auth link is the one artifact that must never point at a host whose
  # ownership we haven't proven. This is deliberately STRICTER than the
  # serving-path gates (`DomainStrategy#known_custom_domain?` keys on record
  # existence): a registered-but-unverified domain still serves pages, but its
  # auth links build on the canonical host until its TXT record verifies.
  #
  # ## FAIL CLOSED on a datastore blip
  #
  # `from_display_domain` is the RAISING loader — a Redis error propagates
  # rather than reading as "no such tenant". We rescue it to `false`, i.e. the
  # candidate is rejected and URL construction falls back to the canonical
  # host. A datastore outage must never widen the set of hosts an auth link
  # can point at, so the failure mode is deliberately the safe one: it can
  # only ever be over-strict (a real custom domain briefly builds links on the
  # canonical host during an outage), never over-permissive.
  #
  # We resolve the tenant record directly rather than gating on
  # `env['onetime.domain_strategy'] == :custom`. That classification degrades
  # to `:invalid` whenever `Chooserator` raises — including whenever the
  # configured canonical host is unparseable, which the integration
  # environment actually has — so a real customer domain can carry a correct
  # `display_domain` alongside an `:invalid` strategy. Reading the record here
  # keeps those genuine custom domains working while still failing closed on a
  # true datastore failure (the loader raises, we rescue).
  #
  # ## Canonical-set exclusion, and nil
  #
  # Canonical-set hosts (features.domains.default, site.host, link_domains) are
  # excluded up front — a split deployment's second canonical host must not
  # read as a custom domain, and a canonical host never has a tenant record
  # anyway. Both tiers are canonical-filtered, and nil keeps the caller's own
  # derivation, which for the callers below is a CANONICAL host — never the
  # request authority. DetectHost rejects `localhost`/`127.0.0.1` outright, so
  # a dev flow never reaches here with a host to swap in.
  #
  # A canonical request still keeps ITS OWN canonical host, though:
  # `canonical_request_host` accepts a trusted candidate exactly when
  # `DomainStrategy.canonical_host?` proves it is a member of the canonical
  # set, so a split deployment's second canonical host (eu.example.com in
  # link_domains) builds its links on itself rather than being rewritten to
  # site.host. That keeps the allowlist property intact — every host an auth
  # URL can carry is either a TXT-verified tenant or a canonical-set member,
  # and the value never comes from `request.host` / a forwarded header.
  #
  # Consumers: Auth::Config::Features::OmniAuth.full_host_for (SSO
  # redirect_uri / callback_url) and Auth::Config::Overrides::PublicBaseUrl
  # (Rodauth `base_url`, hence every `*_email_link`, and the WebAuthn origin).
  #
  module PublicHost
    # @param env [Hash] Rack environment
    # @return [String, nil] the public host, or nil to keep the caller's own
    #   (canonical) derivation — no resolved host, only canonical-set ones, or
    #   no verified tenant record for any candidate
    def self.resolve(env)
      candidates = [env['onetime.display_domain'], env[Rack::DetectHost.result_field_name]]

      candidates.map(&:to_s).find do |host|
        served_custom_host?(host)
      end
    end

    # Positive-evidence host allowlist test (finding G-01).
    #
    # True only when +host+ is non-empty, is NOT one of the canonical hosts,
    # and names a CustomDomain whose ownership is TXT-VERIFIED (`verified`).
    # Registration alone doesn't prove control of the host, and an auth link
    # must never point at a host whose ownership is unproven. Uses the raising
    # loader so a datastore failure fails CLOSED here (rescue -> false) rather
    # than reading as an absent tenant — a link then builds on the canonical
    # host, never on an unverifiable one.
    #
    # @param host [String] a candidate host (already coerced to String)
    # @return [Boolean]
    def self.served_custom_host?(host)
      return false if host.empty?
      # Port- and case-insensitive, and covers the whole canonical set
      # (features.domains.default, site.host, link_domains).
      return false if Onetime::Middleware::DomainStrategy.canonical_host?(host)

      record = Onetime::CustomDomain.from_display_domain(host)
      !record.nil? && !!record.verified # boolean_field native
    rescue StandardError
      # Datastore blip (or any unexpected error): fail closed. The auth link
      # falls back to the canonical host rather than an unverifiable one.
      false
    end

    # Absolute origin for the public host: `scheme://host[:port]`.
    #
    # Reproduces Rack::Request#base_url with the authority's host swapped:
    # scheme and port still come from the request (both honor the proxy's
    # X-Forwarded-* the same way they did before), so only the hostname
    # changes, and only on registered custom domains.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] origin, or nil when #resolve declines
    def self.base_url(env)
      host = resolve(env)
      return nil if host.nil?

      origin_for(env, host)
    end

    # The request's own host when it is a MEMBER OF THE CANONICAL SET — the
    # tier between a verified tenant and the configured site.host fallback.
    #
    # Read from the same trusted candidates as #resolve (display_domain /
    # DetectHost's result — never Rack's forwarded-honoring `request.host`),
    # and accepted only on `DomainStrategy.canonical_host?`'s say-so, so this
    # cannot introduce a host the deployment does not already serve as its
    # own. It exists for split deployments: a request arriving on a secondary
    # canonical host (link_domains, features.domains.default) keeps its links
    # on that host instead of being rewritten to site.host.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] the request's canonical host, or nil when no
    #   trusted candidate is in the canonical set
    def self.canonical_request_host(env)
      candidates = [env['onetime.display_domain'], env[Rack::DetectHost.result_field_name]]

      candidates.map(&:to_s).find do |host|
        !host.empty? && Onetime::Middleware::DomainStrategy.canonical_host?(host)
      end
    end

    # Absolute origin for the request's own canonical host (see
    # #canonical_request_host). Scheme and port come from the request, the
    # same way #base_url builds a tenant origin.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] origin, or nil when #canonical_request_host declines
    def self.canonical_request_base_url(env)
      host = canonical_request_host(env)
      return nil if host.nil?

      origin_for(env, host)
    end

    # `scheme://host[:port]` for an ALREADY-ALLOWLISTED host. Reproduces
    # Rack::Request#base_url with the authority's host swapped: scheme and
    # port still come from the request (both honor the proxy's X-Forwarded-*
    # the same way they did before), so only the hostname changes.
    #
    # ## The host may ALREADY carry a port — strip it before appending one
    #
    # The port comes from the request, so +host+ must contribute the hostname
    # and nothing else. A canonical-set candidate routinely arrives with a
    # port attached: `site.host` is configured as an authority (`localhost:7143`
    # in the full-auth E2E lane, `secrets.internal:8443` on an on-prem install),
    # `DomainStrategy#call` copies it verbatim into `display_domain` whenever
    # domains are disabled, and `canonical_host?` matches it PORT-INSENSITIVELY
    # — so `canonical_request_host` legitimately hands back `localhost:7143`.
    # Interpolating that straight into the authority yielded
    # `http://localhost:7143:7143/verify-account?key=…`: an unparseable URL in
    # every real verification and reset email the deployment sends.
    #
    # Normalizing through `extract_hostname` is what makes the two agree — it
    # is the same port-stripping normalizer `canonical_host?` admits the
    # candidate with. IPv6 literals come back bare (`2001:db8::1`), so they are
    # re-bracketed per RFC 3986 §3.2.2 before a port can be appended.
    #
    # @param env [Hash] Rack environment
    # @param host [String] an allowlisted host (verified tenant or canonical),
    #   with or without a port
    # @return [String] origin
    def self.origin_for(env, host)
      request      = Rack::Request.new(env)
      hostname     = Onetime::Utils::DomainParser.extract_hostname(host) || host.to_s
      hostname     = "[#{hostname}]" if hostname.include?(':') # bare IPv6 literal
      port         = request.port
      scheme       = request.scheme
      default_port = scheme == 'https' ? 443 : 80
      authority    = port && port != default_port ? "#{hostname}:#{port}" : hostname

      "#{scheme}://#{authority}"
    end
    private_class_method :origin_for

    # The configured CANONICAL host — the same value the web app builds its
    # baseuri from (Core::Views::InitializeViewVars reads site.host). This is
    # the fail-closed fallback host for every auth-URL consumer, and it is
    # request-independent BY DESIGN: no auth URL host may ever be derived from
    # `request.host` / a client-settable forwarded header.
    #
    # @return [String, nil] the canonical host, or nil when unconfigured
    def self.canonical_host
      host = OT.conf.dig('site', 'host')
      host.to_s.empty? ? nil : host
    end

    # Absolute canonical origin: `scheme://canonical_host`. Scheme follows the
    # site.ssl config (the same rule InitializeViewVars uses for baseuri), NOT
    # the request — so this cannot be steered by a forwarded header either.
    #
    # @return [String, nil] canonical origin, or nil when the host is unset
    def self.canonical_base_url
      host = canonical_host
      return nil if host.nil?

      scheme = OT.conf.dig('site', 'ssl') == false ? 'http' : 'https'
      "#{scheme}://#{host}"
    end
  end
end
