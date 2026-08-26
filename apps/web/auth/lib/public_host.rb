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
  # TWO TIERS, most trustworthy first — the same sources, in the same order,
  # that Auth::Config::Hooks::OmniAuthTenant.public_host keys tenant
  # credential resolution on. Keep the two in step: a redirect_uri or an email
  # link built from a different host than the one whose credentials were
  # injected is a broken flow either way.
  #
  # `display_domain` is only an answer about THIS request when DomainStrategy
  # actually classified the host. That middleware pins it to the canonical
  # host on two paths that say nothing about where the browser is — the
  # domains feature being off, and a detected host failing validation — so a
  # canonical-set value carries no information.
  #
  # DetectHost's result is the next rung: the same host DomainStrategy would
  # have classified, already normalized, and honored from forwarded headers
  # ONLY behind trusted infrastructure. It covers the case `display_domain`
  # cannot — the whole test topology, and any deployment running
  # `domains.enabled: false` behind a Host-rewriting proxy, where DetectHost
  # still ran and still holds the browser's host.
  #
  # Both tiers are canonical-filtered, and nil keeps the caller's own
  # derivation — which is what the canonical set and local development want.
  # DetectHost rejects `localhost`/`127.0.0.1` outright, so a dev flow never
  # reaches here with a host to swap in and cannot be rewritten to the
  # canonical domain mid-flight.
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
    #   derivation (no resolved host, or only canonical-set ones)
    def self.resolve(env)
      candidates = [env['onetime.display_domain'], env[Rack::DetectHost.result_field_name]]

      candidates.map(&:to_s).find do |host|
        # Port- and case-insensitive, and covers the whole canonical set
        # (features.domains.default, site.host, link_domains) — a split
        # deployment's second canonical host must not read as a custom domain.
        !host.empty? && !Onetime::Middleware::DomainStrategy.canonical_host?(host)
      end
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
