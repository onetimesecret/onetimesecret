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
  # Scoped to display domains DomainStrategy actually resolved. That
  # middleware pins `display_domain` to the canonical host on two paths that
  # say nothing about where the browser is — the domains feature being off,
  # and a detected host failing validation — and honoring those would rewrite
  # a local `localhost:3000` (or any unrecognized-host) URL to the canonical
  # domain. A display domain outside the canonical set cannot have come from
  # either path: it is DetectHost's answer for this request, already
  # validated. Canonical-set hosts keep the stock derivation, which for a
  # genuine canonical request produces the same host anyway.
  #
  # Deliberately NOT gated on `domain_strategy == :custom`. That
  # classification degrades to `:invalid` whenever `Chooserator` raises — a
  # datastore blip, or an unparseable canonical host — and it does so
  # independently of `display_domain`, which stays correct. Gating on it would
  # drop back to the origin target exactly when the tenant lookup still
  # succeeds.
  #
  # Consumers: Auth::Config::Features::OmniAuth.full_host_for (SSO
  # redirect_uri / callback_url) and Auth::Config::Overrides::PublicBaseUrl
  # (Rodauth `base_url`, hence every `*_email_link` and the WebAuthn origin).
  #
  module PublicHost
    # @param env [Hash] Rack environment
    # @return [String, nil] the public host, or nil to keep the caller's own
    #   derivation (blank display domain, or a canonical-set host)
    def self.resolve(env)
      display_domain = env['onetime.display_domain'].to_s
      return nil if display_domain.empty?

      # Port- and case-insensitive, and covers the whole canonical set
      # (features.domains.default, site.host, link_domains) — a split
      # deployment's second canonical host must not read as a custom domain.
      return nil if Onetime::Middleware::DomainStrategy.canonical_host?(display_domain)

      display_domain
    end

    # Absolute origin for the public host: `scheme://host[:port]`.
    #
    # Reproduces Rack::Request#base_url with the authority's host swapped:
    # scheme and port still come from the request (both honor the proxy's
    # X-Forwarded-* the same way they did before), so only the hostname
    # changes, and only on custom domains.
    #
    # @param env [Hash] Rack environment
    # @return [String, nil] origin, or nil when #resolve declines
    def self.base_url(env)
      host = resolve(env)
      return nil if host.nil?

      request      = Rack::Request.new(env)
      port         = request.port
      scheme       = request.scheme
      default_port = scheme == 'https' ? 443 : 80
      authority    = port && port != default_port ? "#{host}:#{port}" : host

      "#{scheme}://#{authority}"
    end
  end
end
