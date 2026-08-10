# lib/onetime/middleware/admin_network_isolation.rb
#
# frozen_string_literal: true

require_relative '../../middleware/detect_host'
require_relative '../utils/admin_host_allowlist'
require_relative '../utils/canonical_hosts'

module Onetime
  module Middleware
    # AdminNetworkIsolation - host and network isolation for the Colonel admin
    # surfaces (`/colonel` shell + `/api/colonel` API).
    #
    # A sibling of IPBan and HealthAccessControl in the universal middleware
    # stack (see Onetime::Application::MiddlewareStack.configure). It gives the
    # deployment a config-selectable posture WITHOUT forking the code, across
    # TWO INDEPENDENT FACTORS. Neither replaces the other, and a request must
    # pass every gate that is ACTIVE:
    #
    #   1. HOST — `site.admin.allowed_hosts` (#4062). WHICH HOSTNAME the admin
    #      surfaces answer on. ACTIVE BY DEFAULT: an empty list falls back to
    #      the deployment's canonical ANCHOR hosts plus their `www.` variants,
    #      so a stock canonical deployment sees no behavior change while a
    #      tenant custom domain (or any other vhost the app answers on) stops
    #      serving the admin console. `*` is the explicit escape hatch. An
    #      explicit list with nothing enforceable in it does not reach here —
    #      Onetime::Config.validate_admin_allowed_hosts! refuses to boot.
    #
    #   2. NETWORK — `site.admin.allowed_cidrs`. WHICH CLIENT IPs may reach the
    #      surfaces. OPT-IN: empty/unset (the self-hosted single-container
    #      default) means this gate is not consulted at all. Set it on cloud to
    #      the private ranges the surfaces should be reachable from (e.g.
    #      Tailscale CGNAT 100.64.0.0/10, an office VPN CIDR, or RFC1918).
    #
    # A request that fails EITHER active gate gets a 404 on `/colonel` and
    # `/api/colonel` — indistinguishable-from-absent, NOT a 403, so the admin
    # surface does not even advertise its existence to an unauthorized host or
    # network. Both gates are defense-in-depth ON TOP OF the two app-layer auth
    # layers (role=colonel at the Otto router + verify_one_of_roles!(colonel:
    # true) in each logic class), which still enforce beneath for any request
    # that does pass.
    #
    # When BOTH gates are inactive the middleware is a strict NO-OP, exactly as
    # before #4062.
    #
    # ## Host resolution
    #
    # The host is read from env[Rack::DetectHost.result_field_name] — the host
    # Rack::DetectHost already validated, and which only honors a forwarded
    # header when the peer was trusted. Three things it deliberately is NOT:
    #
    #   - NOT env['onetime.domain_strategy']. DomainStrategy honors an
    #     `O-Domain-Context` REQUEST HEADER override when
    #     development.domain_context_enabled is on. A header-settable input
    #     must never decide admin reachability.
    #   - NOT HTTP_HOST / HTTP_X_FORWARDED_HOST. Reading those raw would
    #     bypass the trust decision DetectHost already made about the peer.
    #   - NOT the literal string 'rack.detected_host'. The env key name is a
    #     runtime-mutable accessor driven by the DETECTED_HOST env var, so a
    #     hardcoded literal would read nil on a deployment that renames it —
    #     a blanket 404 on both surfaces. Same access pattern DomainStrategy
    #     uses.
    #
    # Both sides of the comparison are normalized identically (downcased, port
    # stripped, trailing root dot stripped) by
    # Onetime::Utils::AdminHostAllowlist, which also decides which configured
    # entries can ever match. Matching is exact and ASCII/A-label only.
    #
    # ## Configured badly vs not configured — the asymmetry
    #
    # Rack::DetectHost never emits `localhost`, `localhost.localdomain`,
    # `127.0.0.1`, `::1`, or ANY IP literal, so the detected host is nil on
    # stock local-dev (shipped default site.host is `localhost:3000`) and on
    # bare-IP self-hosted installs. The two cases that produces are NOT the
    # same and must not be collapsed:
    #
    #   NOBODY CONFIGURED ANYTHING (allowed_hosts empty, anchors unroutable):
    #     the gate goes INERT with a boot WARN. A literally fail-closed default
    #     would 404 `/colonel` on every stock single-container install, which
    #     the network gate was carefully designed never to do.
    #
    #   AN OPERATOR CONFIGURED SOMETHING UNENFORCEABLE (allowed_hosts set, no
    #     entry survives): Onetime::Config.validate_admin_allowed_hosts! raises
    #     at boot, and if that validation was somehow bypassed this middleware
    #     DENIES both surfaces. Going inert here would serve the admin console
    #     on every host from a config whose plain intent was to restrict it —
    #     failing open on a typo. `*` remains the way to turn the gate off.
    #
    # ## Client IP resolution
    #
    # The allowlist check MUST use the trusted-proxy-resolved client IP, never a
    # raw forwarding header, or the allowlist is trivially spoofable by sending
    # `X-Forwarded-For: <an-allowed-ip>`. We resolve from the canonical
    # env['otto.client_ip'] set once by the universal IPPrivacyMiddleware mount
    # (configured from site.network.trusted_proxy via
    # MiddlewareStack.ip_privacy_security_config), with the same
    # Otto::Utils.resolve_client_ip fallback the auth strategies use. This is the
    # identical resolution the rest of the stack relies on, so the network gate
    # agrees with ban checks, sessions, and audit attribution. When the IP cannot
    # be resolved and an allowlist is configured, the request is denied (404) —
    # fail closed.
    #
    # ## Path matching
    #
    # This middleware runs INSIDE each app, after Rack::URLMap has stripped the
    # mount prefix into SCRIPT_NAME. The colonel API app is mounted at
    # `/api/colonel` (PATH_INFO becomes `/info`, `/stats`, …) and the core web
    # app at `/` (PATH_INFO stays `/colonel`). We reconstruct the full request
    # path from SCRIPT_NAME + PATH_INFO so both surfaces match regardless of
    # which app is handling the request.
    #
    class AdminNetworkIsolation
      # The surfaces this middleware guards. Named in every boot log so an
      # operator can grep for what is (and is not) gated.
      SURFACES = %w[/colonel /api/colonel].freeze

      # Sole-entry escape hatch that disables the HOST gate. The network gate
      # is unaffected by it. Needed by self-hosted installs reached by bare IP
      # or by a hostname that is not the configured canonical domain.
      HOST_WILDCARD = Onetime::Utils::AdminHostAllowlist::WILDCARD

      def initialize(app)
        @app             = app
        @logger          = Onetime.get_logger('AdminNetworkIsolation')

        # Both allowlists are resolved ONCE, here — the process has booted and
        # nothing re-reads config per request. The host gate carries its own
        # active flag rather than deriving one from emptiness: an ACTIVE gate
        # with an EMPTY allowlist is the fail-closed backstop, and "inactive"
        # must not be reachable by accident.
        @allowed_ranges              = parse_allowed_cidrs(configured_cidrs)
        @allowed_hosts, @host_gate   = resolve_host_gate

        log_boot_posture
      end

      def call(env)
        # Cheapest discriminator first: any path that is not an admin surface
        # leaves this middleware untouched, whatever the gates are set to.
        full_path = request_path(env)
        return @app.call(env) unless admin_surface?(full_path)

        # Both gates inactive — the pre-#4062 self-hosted default. Strict
        # NO-OP: the two app-layer auth layers are the sole gate.
        return @app.call(env) unless host_gate_active? || network_gate_active?

        # Each gate is consulted INDEPENDENTLY and only while active; either
        # denial produces the identical 404, so a host denial, a network
        # denial, and an absent route are indistinguishable to the client.
        return not_found_response(full_path) if host_denied?(env, full_path)
        return not_found_response(full_path) if network_denied?(env, full_path)

        @app.call(env)
      end

      private

      # --- gates ---------------------------------------------------------

      def host_gate_active?
        @host_gate
      end

      def network_gate_active?
        !@allowed_ranges.empty?
      end

      # Host gate. Fails closed: an active gate with an unresolvable (nil or
      # empty) detected host denies, mirroring the nil-IP path in #allowed?.
      # The denial WARN is distinct from the network one so operators can tell
      # the two factors apart in logs; the allowlist is never echoed into the
      # response, only into the log.
      def host_denied?(env, full_path)
        return false unless host_gate_active?

        host = detected_host(env)
        return false if host_allowed?(host)

        @logger.warn 'Admin surface access denied by host allowlist',
          {
            host: host,
            path: full_path,
            method: env['REQUEST_METHOD'],
          }

        true
      end

      # Network (CIDR) gate. Unchanged semantics from before #4062.
      def network_denied?(env, full_path)
        return false unless network_gate_active?

        client_ip = resolve_client_ip(env)
        return false if allowed?(client_ip)

        @logger.warn 'Admin surface access denied by network isolation',
          {
            ip: client_ip,
            path: full_path,
            method: env['REQUEST_METHOD'],
          }

        true
      end

      # Full request path independent of where the app is mounted. Rack::URLMap
      # moves the mount prefix into SCRIPT_NAME, so PATH_INFO alone would be
      # `/info` inside the colonel API app (mounted at /api/colonel).
      def request_path(env)
        "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}"
      end

      def admin_surface?(path)
        colonel_shell?(path) || colonel_api?(path)
      end

      def colonel_shell?(path)
        path == '/colonel' || path.start_with?('/colonel/')
      end

      def colonel_api?(path)
        path == '/api/colonel' || path.start_with?('/api/colonel/')
      end

      def allowed?(client_ip)
        return false if client_ip.nil? || client_ip.empty?

        addr = IPAddr.new(client_ip)
        @allowed_ranges.any? { |range| range.include?(addr) }
      rescue IPAddr::InvalidAddressError
        false
      end

      # The validated detected host, normalized the same way the configured
      # entries were. The env KEY is asked for at call time
      # (Rack::DetectHost.result_field_name is a runtime-mutable accessor);
      # never hardcode 'rack.detected_host'.
      def detected_host(env)
        normalize_host(env[Rack::DetectHost.result_field_name])
      end

      # ONE normalization for BOTH sides of the comparison. Delegated to the
      # shared classifier rather than reimplemented: the configured entries were
      # shaped by AdminHostAllowlist.normalize_host at construction, and a
      # second local copy here is how an exact-match gate silently stops
      # matching (a stripped port on one side, a kept trailing dot on the
      # other).
      def normalize_host(value)
        Onetime::Utils::AdminHostAllowlist.normalize_host(value)
      end

      # Exact membership against the effective host allowlist. Nil/empty fails
      # closed — an active host gate that cannot see a host denies.
      def host_allowed?(host)
        return false if host.nil? || host.empty?

        @allowed_hosts.include?(host)
      end

      # Resolve the client IP from the trusted-proxy-aware canonical value, with
      # the same fallback the auth strategies use. Never trusts a raw header.
      def resolve_client_ip(env)
        canonical = env['otto.client_ip']
        return canonical if canonical && !canonical.empty?

        Otto::Utils.resolve_client_ip(env, env['otto.security_config'])
      rescue StandardError => ex
        @logger.warn "Client IP resolution failed; denying admin surface: #{ex.message}"
        nil
      end

      def configured_cidrs
        site_admin_list('allowed_cidrs')
      end

      def configured_hosts
        site_admin_list('allowed_hosts')
      end

      # One reader for both site.admin.* lists. Config may be entirely absent
      # (partial boot, specs); an unreadable config must never raise out of
      # this middleware's constructor.
      def site_admin_list(key)
        OT.conf.dig('site', 'admin', key)
      rescue StandardError
        nil
      end

      def parse_allowed_cidrs(value)
        Array(value).filter_map do |cidr|
          next if cidr.to_s.strip.empty?

          IPAddr.new(cidr.to_s.strip)
        rescue IPAddr::InvalidAddressError
          @logger.warn "Invalid CIDR in site.admin.allowed_cidrs, skipping: #{cidr}"
          nil
        end
      end

      # Resolve the host gate ONCE at construction, from
      # site.admin.allowed_hosts and — only when that is unset — the canonical
      # anchors.
      #
      # @return [Array(Array<String>, Boolean)] the allowlist, and whether the
      #   gate is active. ACTIVE with an EMPTY allowlist denies everything;
      #   that is the backstop, not an accident.
      def resolve_host_gate
        configured = Onetime::Utils::AdminHostAllowlist.classify(configured_hosts)

        return anchor_host_gate if configured.empty?
        return wildcard_host_gate if configured.wildcard_only?

        configured_host_gate(configured)
      end

      # An operator wrote a list. Enforce whatever survived classification.
      def configured_host_gate(classified)
        warn_dropped_wildcard if classified.wildcard
        warn_rejected_entries(classified.rejected)

        return [classified.hosts, true] if classified.hosts.any?

        # BACKSTOP — normally unreachable: Onetime::Config
        # .validate_admin_allowed_hosts! refuses this config at boot with a
        # message naming every rejected entry. Reaching it means that
        # validation did not run (an embedding that builds a Rack app without
        # Config.raise_concerns). An explicit allowlist with nothing
        # enforceable must DENY, never disable itself: the operator's plain
        # intent was to restrict, and `*` is how you ask for the opposite.
        # An operator reading this line is debugging an outage, not auditing an
        # invariant: lead with what is happening to the surfaces, then the
        # cause, then the remedy.
        @logger.warn 'Admin host allowlist has no enforceable entry; denying both admin surfaces',
          {
            entries: classified.rejected.map(&:first),
            surfaces: SURFACES,
            note: '/colonel and /api/colonel are returning 404 to EVERY request because no entry in ' \
                  'site.admin.allowed_hosts can match a detected host. This config is normally ' \
                  'rejected at boot, so boot-time validation did not run here. Set ' \
                  'ADMIN_ALLOWED_HOSTS to a routable hostname, unset it to allow the canonical ' \
                  'host only, or set it to * to disable the host gate',
          }

        [[], true]
      end

      # `*` as the sole entry: the documented escape hatch.
      def wildcard_host_gate
        @logger.warn 'Admin host allowlist DISABLED by `*`',
          {
            surfaces: SURFACES,
            note: 'both admin surfaces answer on every hostname the app serves; the CIDR gate is unaffected',
          }

        [[], false]
      end

      # Nobody configured anything: fall back to the canonical anchors, plus
      # their `www.` variants.
      #
      # THE INERT RULE lives here and ONLY here. When the anchors yield nothing
      # Rack::DetectHost could emit — stock local-dev (`site.host` defaults to
      # `localhost:3000`) or a bare-IP self-hosted install — the gate goes
      # inactive with a WARN rather than 404ing `/colonel` on an install nobody
      # misconfigured. Contrast configured_host_gate, which denies: there the
      # operator did write something.
      #
      # Judged BEFORE `www.` expansion: `localhost` is not emittable but a
      # synthesized `www.localhost` would be, which would defeat the rule.
      def anchor_host_gate
        anchors = Onetime::Utils::AdminHostAllowlist.classify(canonical_anchor_hosts)
        return [with_www_variants(anchors.hosts), true] if anchors.hosts.any?

        @logger.warn 'Admin host allowlist INACTIVE: no routable hostname configured',
          {
            source: 'canonical anchors',
            hosts: canonical_anchor_hosts,
            surfaces: SURFACES,
            note: 'localhost and bare-IP hosts are never detected as a host; set ADMIN_ALLOWED_HOSTS ' \
                  '(or site.host / DEFAULT_DOMAIN) to a routable hostname to enable the host gate',
          }

        [[], false]
      end

      # States only what this check decided. Whether anything is left to
      # enforce is the next check's business — and its answer may be "nothing",
      # which is why this must not promise that named hosts are enforced.
      def warn_dropped_wildcard
        @logger.warn 'Dropped `*` from site.admin.allowed_hosts: it is only honored as the sole entry',
          {
            note: 'list `*` alone to disable the host gate',
          }
      end

      # Entries that can never match are dropped, not fatal, as long as
      # something enforceable remains. Named at boot so the operator can see
      # WHY the effective allowlist is smaller than what they wrote.
      def warn_rejected_entries(rejected)
        return if rejected.empty?

        @logger.warn 'Ignoring unusable entries in site.admin.allowed_hosts',
          {
            entries: Onetime::Utils::AdminHostAllowlist.describe_rejections(rejected),
          }
      end

      # The fallback allowlist source: the deployment's ANCHOR hosts only —
      # features.domains.default and site.host.
      #
      # NOT CanonicalHosts.hosts / normalized_hosts / canonical_host?: those
      # include the features.domains.link_domains pool (#4063), so using them
      # would serve the admin console on every operator short-link domain —
      # the exact inverse of what the link pool exists to do. NOT
      # DomainStrategy.canonical_host? either: its answer depends on
      # features.domains.enabled and on lazily-initialized class state.
      def canonical_anchor_hosts
        Onetime::Utils::CanonicalHosts.normalized_anchor_hosts
      end

      # Admit the `www.` sibling of each anchor, matching the tolerance
      # DomainStrategy::Chooserator.equal_to? applies to anchors (and only to
      # anchors). Neither CanonicalHosts nor DomainParser synthesizes it.
      def with_www_variants(hosts)
        expanded = hosts.flat_map do |host|
          if host.start_with?('www.')
            [host, host.delete_prefix('www.')]
          else
            [host, "www.#{host}"]
          end
        end

        expanded.uniq
      end

      # One INFO line per process describing the effective posture of BOTH
      # factors, including when a gate is off — so "off" is distinguishable
      # from "misconfigured" without diffing config against source.
      #
      # `trusted_proxy` is on this line, and deliberately not on one of its own:
      # it qualifies the two gate states beside it. Both gates judge inputs that
      # a proxy layer determines (the detected host; the resolved client IP), so
      # `host_gate: active` correlated with `trusted_proxy: disabled` is the
      # whole point — see #trusted_proxy_posture.
      def log_boot_posture
        @logger.info 'Admin surface isolation posture',
          {
            host_gate: host_gate_active? ? 'active' : 'inactive',
            allowed_hosts: @allowed_hosts,
            network_gate: network_gate_active? ? 'active' : 'inactive',
            allowed_cidrs: effective_cidrs,
            trusted_proxy: trusted_proxy_posture,
            surfaces: SURFACES,
          }
      end

      # The parsed ranges as an operator would have written them. IPAddr#to_s
      # drops the mask, so a configured 100.64.0.0/10 would otherwise log as
      # `100.64.0.0` — a /10 rendered as what looks like a single host, on the
      # one line an operator reads to confirm the posture took effect.
      def effective_cidrs
        @allowed_ranges.map { |range| "#{range}/#{range.prefix}" }
      end

      # Whether the deployment declares a trusted reverse proxy, and in which
      # mode. Read through the SAME predicate that decides how the universal
      # IP-privacy mount is configured
      # (Onetime::Application::MiddlewareStack.trusted_proxy_enabled?, consumed
      # by .ip_privacy_security_config), so this line cannot report a posture
      # the stack does not actually have.
      #
      # WHY IT IS LOGGED HERE: with trusted_proxy DISABLED — the shipped
      # default — neither gate's input is authenticated. Rack::DetectHost falls
      # back to a legacy heuristic that trusts any peer on a private or loopback
      # address to set a forwarded host header, and otto resolves the client IP
      # from REMOTE_ADDR. On a shared container network, or anywhere with SSRF
      # egress, that is what these gates judge. `host_gate: active` alone reads
      # stronger than it is.
      #
      # The mode is reported because it changes how the client IP is resolved —
      # and because depth mode is currently broken (#4024).
      #
      # No require_relative for MiddlewareStack: it requires THIS file (the
      # mount), so the dependency only runs the other way. The constant is
      # resolved at call time, by which point anything that mounts this
      # middleware has loaded it; the rescue covers an embedding that builds it
      # standalone. A boot log line must never be the thing that fails a boot.
      def trusted_proxy_posture
        return 'disabled' unless Onetime::Application::MiddlewareStack.trusted_proxy_enabled?

        # Reproduces MiddlewareStack.ip_privacy_security_config's own default
        # for an enabled-but-modeless block. There is no shared reader for the
        # MODE (only for `enabled`), so this expression is duplicated.
        #
        # TODO: consolidate the trusted-proxy config readers. `enabled` is
        # already reimplemented verbatim in THREE places —
        # Onetime::Application::MiddlewareStack.trusted_proxy_enabled?,
        # Onetime::Security::ResetRequestRateLimiter, and
        # Onetime::Security::CreateAccountRateLimiter — and this adds a fourth
        # site reading `mode`. One accessor pair (enabled + mode) should serve
        # all of them. Out of scope for #4062; tracked separately.
        mode = OT.conf.dig('site', 'network', 'trusted_proxy', 'mode').to_s.strip
        mode = 'filter' if mode.empty?

        "enabled (mode=#{mode})"
      rescue StandardError
        'unknown'
      end

      # 404, not 403: the surface must be indistinguishable from absent to an
      # unauthorized network. Content type mirrors the surface (JSON for the API,
      # HTML for the shell) so the response looks like a normal not-found.
      def not_found_response(path)
        if path.start_with?('/api')
          [
            404,
            { 'Content-Type' => 'application/json' },
            [JSON.generate({ error: 'Not Found' })],
          ]
        else
          [
            404,
            { 'Content-Type' => 'text/html; charset=utf-8' },
            [html_body],
          ]
        end
      end

      def html_body
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>404 Not Found</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                  background-color: #f9fafb;
                  color: #374151;
                  margin: 0;
                  padding: 40px 20px;
                  text-align: center;
                }
                .container {
                  max-width: 400px;
                  margin: 0 auto;
                }
                h1 {
                  font-size: 1.5rem;
                  margin-bottom: 0.5rem;
                }
                p {
                  color: #6b7280;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>404 Not Found</h1>
                <p>The requested resource was not found.</p>
              </div>
            </body>
          </html>
        HTML
      end
    end
  end
end
