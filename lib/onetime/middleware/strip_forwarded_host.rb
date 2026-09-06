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
    # ## Host only — the other RFC 7239 parameters survive
    #
    # `X-Forwarded-Host` carries nothing but an authority, so it is deleted
    # outright. The RFC 7239 `Forwarded` header, however, multiplexes host
    # alongside `proto`, `for`, and `by` — and Rack reads those too
    # (`Request#scheme` via `forwarded_scheme`, `#forwarded_for`,
    # `#forwarded_port`). A deployment whose proxy speaks only `Forwarded`
    # (no `X-Forwarded-Proto`) would lose its TLS scheme — and every absolute
    # URL built after this middleware — if the whole header vanished. So for
    # `Forwarded` we surgically remove the `host=` parameters and keep the
    # rest; the header is deleted only when nothing else remains. With no
    # `host=` present, Rack's `forwarded_authority` finds nothing at the
    # `:forwarded` priority and falls through to `X-Forwarded-Host` — which
    # this middleware has already deleted.
    #
    # Since Onetime::Initializers::ConfigureRack pins
    # `Rack::Request.forwarded_priority = [:x_forwarded]`, Rack no longer
    # consults `Forwarded` for ANY of host/for/port/proto, so the surgical
    # preservation above is moot for Rack itself. It is kept because other
    # readers still consume the raw header from the env — Otto's IP privacy
    # middleware in depth mode with `trusted_proxy.header: Forwarded`, and
    # its redacted fingerprint — and because the priority is process-global
    # state a future require could reset; the env-level strip holds either way.
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

      # RFC 7239 — multiplexes host with proto/for/by: host params are
      # removed, the rest is preserved.
      FORWARDED = 'HTTP_FORWARDED'

      def initialize(app)
        @app = app
      end

      def call(env)
        env.delete(X_FORWARDED_HOST)

        if (raw = env[FORWARDED])
          stripped = self.class.without_host_params(raw)
          if stripped.nil?
            env.delete(FORWARDED)
          else
            env[FORWARDED] = stripped
          end
        end

        @app.call(env)
      end

      # Rebuild an RFC 7239 `Forwarded` value with every `host=` parameter
      # removed, preserving the element (comma) and parameter (semicolon)
      # structure — and therefore the per-hop association of the surviving
      # `proto`/`for`/`by` parameters. Splits are quote-aware: a
      # quoted-string value (with backslash escapes) may contain `,` or `;`
      # without ending the element or parameter, matching how
      # Rack::Utils.forwarded_values tokenizes the header.
      #
      # @param raw [String] the incoming Forwarded header value
      # @return [String, nil] the value without host params, or nil when no
      #   parameter survives (caller deletes the header)
      def self.without_host_params(raw)
        kept_elements = split_unquoted(raw, ',').filter_map do |element|
          kept = split_unquoted(element, ';').map(&:strip).reject do |pair|
            pair.empty? || pair.split('=', 2).first.to_s.strip.downcase == 'host'
          end
          kept.join(';') unless kept.empty?
        end

        kept_elements.empty? ? nil : kept_elements.join(', ')
      end

      # Split +value+ on +separator+, ignoring separators inside RFC 7230
      # quoted-strings (backslash escapes honored).
      #
      # @param value [String]
      # @param separator [String] a single character
      # @return [Array<String>]
      def self.split_unquoted(value, separator)
        parts     = []
        current   = +''
        in_quotes = false
        escaped   = false

        value.each_char do |char|
          if in_quotes
            current << char
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == '"'
              in_quotes = false
            end
          elsif char == '"'
            in_quotes = true
            current << char
          elsif char == separator
            parts << current
            current = +''
          else
            current << char
          end
        end

        parts << current
        parts
      end
    end
  end
end
