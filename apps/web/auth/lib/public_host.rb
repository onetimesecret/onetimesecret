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
  # anyway. Both tiers are canonical-filtered, and nil from `resolve` /
  # `base_url` means "not a tenant request" — the caller then continues down
  # the canonical tiers below, never to the request authority.
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
  # ## One chain for every auth URL (#4517)
  #
  # `allowlisted_base_url` / `allowlisted_host` compose the tiers in the one
  # order every auth-URL consumer must share:
  #
  #   1. the TXT-verified tenant host the request resolved to (`resolve`)
  #   2. the request's own host when it is in the canonical set
  #      (`canonical_request_host`)
  #   3. the configured canonical host, request-independent (`canonical_host`)
  #
  # A consumer may append its own last resort BEHIND tier 3 for the
  # "site.host unconfigured" misconfiguration, and nothing else. Rodauth's
  # `base_url` override has read this chain since the G-01 host-allowlist
  # work (#4319; #4221 introduced only the tenant tier); OmniAuth's
  # `full_host` had only tier 1 and fell straight to Rack's authority, so an
  # SSO redirect_uri on the canonical host carried the raw `Host:` header
  # verbatim — including a doubled `Host: a, a` from a misconfigured
  # proxy_set_header (#4517) — while the email link for the same request was
  # built on the canonical host. The two must never disagree about the host,
  # so both read here.
  #
  # Local development is served by tier 2: DomainStrategy pins
  # `display_domain` to the primary canonical host whenever the domains
  # feature is off or the detected host fails validation (DetectHost rejects
  # `localhost` / `127.0.0.1` outright). That host is features.domains.default
  # when domains are enabled and site.host otherwise — in the dev configs,
  # site.host, which IS the host the dev browser is on. A dev request whose
  # browser host differs from site.host builds its SSO URLs on site.host,
  # exactly as its email links already do — set HOST to the host you browse.
  #
  # Tier 2 resolves the selected host back to its configured canonical
  # authority. An explicit configured port wins over the request port, so a
  # doubled, unparseable `Host:` cannot drop it; when config has no port, the
  # request / forwarded port behavior is unchanged.
  #
  # Consumers: Auth::Config::Features::OmniAuth.full_host_for (SSO
  # redirect_uri / callback_url, SAML ACS URL and SP entity ID) and
  # Auth::Config::Overrides::PublicBaseUrl (Rodauth `base_url`, hence every
  # `*_email_link`, and the WebAuthn origin).
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

    # Trusted browser host for WebAuthn. Unlike auth-link generation, WebAuthn
    # does not redirect or disclose a credential to this host: a mismatch makes
    # the browser ceremony fail. DomainStrategy has already sanitized and
    # classified `onetime.display_domain`, and a custom classification also
    # carries the exact record loaded during that decision.
    #
    # @return [String, nil]
    def self.webauthn_host(env)
      strategy = env['onetime.domain_strategy'].to_s
      return nil unless %w[canonical subdomain custom].include?(strategy)
      return nil if strategy == 'custom' && env['onetime.custom_domain'].nil?

      host = env['onetime.display_domain'].to_s
      return nil if host.empty?
      return nil unless Onetime::Utils::DomainParser.basically_valid?(host)

      host
    end

    # Exact browser origin for a host admitted by {webauthn_host}.
    #
    # @return [String, nil]
    def self.webauthn_base_url(env)
      host = webauthn_host(env)
      host && origin_for(env, host)
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
    # @return [String, nil] the matching configured canonical authority, or
    #   nil when no trusted candidate is in the canonical set
    def self.canonical_request_host(env)
      candidates = [env['onetime.display_domain'], env[Rack::DetectHost.result_field_name]]
      selected   = candidates.map(&:to_s).find do |host|
        !host.empty? && Onetime::Middleware::DomainStrategy.canonical_host?(host)
      end

      canonical_authority_for(selected)
    end

    # Absolute origin for the request's own canonical host (see
    # #canonical_request_host). Scheme comes from the request. An explicit
    # port on the trusted configured authority wins; otherwise the request /
    # forwarded port is retained, as for #base_url.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] origin, or nil when #canonical_request_host declines
    def self.canonical_request_base_url(env)
      host = canonical_request_host(env)
      return nil if host.nil?

      origin_for(env, host, preferred_port: explicit_port(host))
    end

    # The origin every auth URL for this request builds on: the shared
    # three-tier chain (see "One chain for every auth URL" above).
    #
    #   1. #base_url                   — verified tenant host, request scheme/port
    #   2. #canonical_request_base_url — the request's configured canonical
    #                                    authority and request scheme
    #   3. #canonical_base_url         — configured site.host, site.ssl scheme
    #
    # Never `request.host` / Rack's `base_url`: the raw authority is what a
    # client-settable forwarded header or a doubled `Host:` header lands in.
    # nil only when site.host is unconfigured AND the request resolved to no
    # allowlisted host; the caller decides its own last resort for that
    # misconfiguration.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] origin
    def self.allowlisted_base_url(env)
      base_url(env) || canonical_request_base_url(env) || canonical_base_url
    end

    # Host-only counterpart of #allowlisted_base_url, same tiers, same order.
    # For consumers that show the host rather than build a URL from it
    # (transactional email branding), so the host shown and the host linked
    # can never disagree.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] host (a canonical candidate may carry its port)
    def self.allowlisted_host(env)
      resolve(env) || canonical_request_host(env) || canonical_host
    end

    # Resolves an admitted canonical request host back to the configured
    # authority that granted membership. When multiple configured sources use
    # the same normalized hostname, site.host wins because it is the app's
    # configured public authority and the canonical fallback used by this
    # module. Distinct default and link-domain hosts still resolve from
    # DomainStrategy's canonical set.
    #
    # This retains configured ports and prevents a port attached only to the
    # request candidate from becoming trusted through the port-insensitive
    # canonical membership check.
    #
    # @param host [String, nil] selected canonical request host
    # @return [String, nil] matching configured canonical authority
    def self.canonical_authority_for(host)
      return nil if host.nil?

      site_authority = canonical_host
      if Onetime::Utils::DomainParser.hostname_matches?(site_authority, host)
        return site_authority
      end

      authorities = Onetime::Middleware::DomainStrategy.canonical_domains
      if authorities.nil? || authorities.empty?
        authorities = [Onetime::Middleware::DomainStrategy.canonical_domain].compact
      end

      exact = authorities.find do |authority|
        authority.to_s.strip.casecmp?(host.to_s.strip)
      end
      return exact unless exact.nil?

      authorities.find do |authority|
        Onetime::Utils::DomainParser.hostname_matches?(authority, host)
      end
    end
    private_class_method :canonical_authority_for

    # Returns a port only when it is explicit in a configured authority.
    #
    # @param authority [String, nil]
    # @return [Integer, nil]
    def self.explicit_port(authority)
      match = authority.to_s.strip.match(/\A(?:[^:\[\]]+|\[[^\]]+\]):(\d+)\z/)
      match && match[1].to_i
    end
    private_class_method :explicit_port

    # `scheme://host[:port]` for an ALREADY-ALLOWLISTED host. Reproduces
    # Rack::Request#base_url with the authority's hostname swapped. Scheme and,
    # by default, port still come from the request and honor X-Forwarded-*.
    # Canonical callers may supply an explicit configured port, which takes
    # precedence over Rack's parsed request port. Scheme-default ports are
    # omitted either way.
    #
    # Normalizing through `extract_hostname` keeps a port already carried by
    # +host+ from being appended twice. IPv6 literals come back bare
    # (`2001:db8::1`), so they are re-bracketed per RFC 3986 §3.2.2.
    #
    # @param env [Hash] Rack environment
    # @param host [String] an allowlisted host (verified tenant or canonical),
    #   with or without a port
    # @param preferred_port [Integer, nil] trusted configured port override
    # @return [String] origin
    def self.origin_for(env, host, preferred_port: nil)
      request      = Rack::Request.new(env)
      hostname     = Onetime::Utils::DomainParser.extract_hostname(host) || host.to_s
      hostname     = "[#{hostname}]" if hostname.include?(':') # bare IPv6 literal
      port         = preferred_port || request.port
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
