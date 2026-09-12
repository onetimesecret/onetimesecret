# lib/onetime/middleware/strip_forwarded_host.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # StripForwardedHost — remove client-settable forwarded-AUTHORITY signals
    # from the Rack env so `Rack::Request#host` can never carry a host the
    # client chose (finding G-01, defense in depth).
    #
    # ## Why this exists
    #
    # Rack 3.2's `Rack::Request#host` resolves through `forwarded_authority`
    # FIRST: it honors `X-Forwarded-Host` and RFC 7239 `Forwarded` from ANY
    # client, with no proxy-trust gate. Rodauth's stock `base_url` (and any
    # other code reading `request.host`) would therefore build an auth URL on
    # a host the client forged — reset-link poisoning, one click from account
    # takeover on the multi-tenant platform.
    #
    # The primary fix lives in Auth::PublicHost / the base_url override, which
    # allowlist the host to a registered tenant and otherwise fall back to the
    # CANONICAL host, never `request.host`. This middleware is the belt to that
    # brace: with the forwarded-host signals gone, even a direct
    # `request.host` read (a future consumer, a gem) resolves to the `Host:`
    # authority the edge actually received — never a client-supplied one —
    # regardless of the operator's proxy configuration.
    #
    # ## Relationship to otto 2.10
    #
    # otto 2.10 pins `Rack::Request.forwarded_priority` to the family chosen
    # in MiddlewareStack.ip_privacy_security_config ([:x_forwarded] unless
    # depth mode names `Forwarded`), and its IPPrivacyMiddleware deletes every
    # forwarded authority carrier from an untrusted peer once proxy trust is
    # configured. This middleware still runs unconditionally: otto strips
    # nothing while trust is unconfigured (the default deployment), and keeps
    # a trusted peer's carriers because it cannot tell a value the proxy set
    # from one the proxy passed through. Both headers are deleted here, so the
    # host authority that reaches every later reader is `Host:` alone.
    #
    # ## Whole-header delete, scheme handed to `rack.url_scheme`
    #
    # `Forwarded` multiplexes host with `proto`/`for`/`by`. An earlier version
    # of this middleware edited only the `host=` parameters out so a
    # `Forwarded`-only proxy kept its TLS scheme. That needs a second RFC 7239
    # parser, and a parser that disagrees with Rack's on quoting lets a
    # `host=` survive the edit (`for=a"b;host=evil` is enough). Deletion has
    # no such failure mode. The one thing Rack legitimately read from the
    # header — the scheme, under the pinned family — is resolved by Rack
    # itself BEFORE the delete and written to `rack.url_scheme`, the key
    # `Rack::Request#scheme` falls back to once no forwarded carrier is
    # present. No parsing happens here; Rack's answer before the strip is
    # Rack's answer after it. `X-Forwarded-Proto` and `X-Forwarded-SSL` are
    # not touched, so the X-Forwarded-* family continues to resolve on its
    # own; `for=` has already been consumed by otto's IP resolution, which
    # runs first.
    #
    # ## The write is UPGRADE-ONLY
    #
    # `Rack::Request#scheme` consults a forwarded carrier BEFORE it falls back
    # to `rack.url_scheme`, so under a `[:forwarded]` pin the pre-strip read
    # can answer `http` for a request that is already established as https.
    # Persisting that would be a permanent downgrade: the header is gone a
    # line later, so the https that `rack.url_scheme` still held is not
    # recoverable, and every later secure-cookie / HSTS / origin / URL
    # consumer sees a plaintext request.
    #
    # Two ways an established https reaches here with a `Forwarded: proto=http`
    # attached:
    #
    #   - TLS terminated at the ORIGIN. The Rack server sets
    #     `rack.url_scheme = 'https'` and no `HTTPS` env var, so nothing
    #     outranks the forwarded carrier in `#scheme`.
    #   - Onetime::Middleware::AssumeHttps, which sets `env['HTTPS'] = 'on'`
    #     alongside the scheme. `#scheme` checks HTTPS first, so this case
    #     already read back as https — but it should not depend on which of
    #     the two keys an upstream happened to set.
    #
    # So the write only ever raises the scheme, mirroring AssumeHttps's own
    # upgrade-only invariant. Downgrading is exactly what a forwarded value is
    # untrusted for; the `Forwarded`-only proxy this write exists to serve is
    # upgrading http to https, which still works.
    #
    # ## What was deleted is recorded by NAME
    #
    # Two readers mounted below this middleware diagnose the edge's forwarding
    # topology from the PRESENCE of these carriers: Onetime::Session's
    # dropped-secure-cookie warning (its `forwarded:` field exists to spot the
    # "edge speaks only `Forwarded`" deployment) and the colonel
    # `/system/proxy-headers` report. Deleting the headers would leave both
    # permanently reporting "absent". So the names of the carriers deleted
    # here are left in `env['onetime.stripped_forwarded_headers']` — names
    # only, never values: `Forwarded` carries the client IP in `for=`, which
    # is exactly what the session warning keeps out of the log.
    #
    # ## Ordering — AFTER DetectHost AND AdminNetworkIsolation, before
    # ## anything reads request.host
    #
    # Two upstream middlewares legitimately consume the raw headers, so both
    # must run first:
    #
    #   - Rack::DetectHost has its OWN trust logic: it honors a forwarded host
    #     ONLY from trusted infrastructure and publishes the result into
    #     env[Rack::DetectHost.result_field_name] (which DomainStrategy then
    #     classifies). That legitimate resolution — the whole custom-domain-
    #     behind-a-proxy topology — MUST keep working.
    #   - Onetime::Middleware::AdminNetworkIsolation's forwarded-host
    #     PROVENANCE rule (host_provenance_trusted?) keys on the PRESENCE of
    #     these headers: "no forwarded header present" is its rule (b) for
    #     accepting a detected host. Stripping before it destroys the evidence
    #     that a detected host was forwarded by an untrusted peer, and the
    #     admin gate would admit exactly the spoof it exists to deny.
    #
    # Nothing between DetectHost and here reads `Rack::Request#host` (the
    # middlewares in between read the resolved env keys, not the raw
    # authority), and the mounted apps run later still, so by the time any
    # `request.host` read happens the forwarded host is gone. DetectHost's
    # and the admin gate's logic are left entirely intact — this only deletes
    # what they have already used.
    class StripForwardedHost
      # Carries only an authority: deleted outright.
      X_FORWARDED_HOST = 'HTTP_X_FORWARDED_HOST'

      # RFC 7239 — multiplexes host with proto/for/by: deleted outright, the
      # scheme Rack resolved from it is carried in rack.url_scheme.
      FORWARDED = 'HTTP_FORWARDED'

      # Rack's fallback scheme key (Rack::RACK_URL_SCHEME).
      RACK_URL_SCHEME = 'rack.url_scheme'

      HTTPS_SCHEME = 'https'

      # Names (env keys) of the carriers this middleware deleted from the
      # request, for the presence-only diagnostics below it. Set only when
      # something was deleted; absent otherwise. See "What was deleted is
      # recorded by NAME" above.
      STRIPPED_HEADERS = 'onetime.stripped_forwarded_headers'

      STRIPPED_CANDIDATES = [X_FORWARDED_HOST, FORWARDED].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        stripped = STRIPPED_CANDIDATES.select { |key| env.key?(key) }

        carry_forwarded_scheme(env) if stripped.include?(FORWARDED)

        stripped.each { |key| env.delete(key) }
        env[STRIPPED_HEADERS] = stripped.freeze unless stripped.empty?

        @app.call(env)
      end

      private

      # Persist the scheme Rack resolves while `Forwarded` is still present,
      # but never below the one already established. See "The write is
      # UPGRADE-ONLY" above.
      def carry_forwarded_scheme(env)
        return if env[RACK_URL_SCHEME] == HTTPS_SCHEME || env['HTTPS'] == 'on'

        env[RACK_URL_SCHEME] = Rack::Request.new(env).scheme
      end
    end
  end
end
