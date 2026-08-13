# lib/onetime/middleware/admin_network_isolation.rb
#
# frozen_string_literal: true

require 'otto/utils'

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
    #      explicit list with nothing enforceable in it DENIES both surfaces
    #      here; Onetime::Config.check_admin_allowed_hosts says so at boot.
    #
    #   2. NETWORK — `site.admin.allowed_cidrs`. WHICH CLIENT IPs may reach the
    #      surfaces. OPT-IN: empty/unset (the self-hosted single-container
    #      default) means this gate is not consulted at all. Set it on cloud to
    #      the private ranges the surfaces should be reachable from (e.g.
    #      Tailscale CGNAT 100.64.0.0/10, an office VPN CIDR, or RFC1918).
    #      A CONFIGURED list with no parseable range in it denies, by the same
    #      rule as the host gate: a list an operator wrote is never silently
    #      disabled.
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
    # Rack::DetectHost already validated. Three things it deliberately is NOT:
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
    # ## Forwarded-host provenance (the extra trust check DetectHost does not
    # ## make, and cannot make for us)
    #
    # DetectHost honors a forwarded host header (X-Forwarded-Host,
    # Apx-Incoming-Host, X-Original-Host, Forwarded) when EITHER the operator
    # configured proxy trust and this peer passed it (otto writes
    # env['otto.via_trusted_proxy'] = true) OR — with no proxy trust configured
    # at all, the SHIPPED DEFAULT — a legacy heuristic: any peer whose
    # REMOTE_ADDR is private or loopback may name the host. That heuristic keeps
    # single-container installs behind a local proxy working, and it is fine for
    # DISPLAY decisions. It is not fine for deciding admin reachability: on every
    # containerised install (and anywhere with SSRF egress) a client that can
    # open a connection from a private address chooses the host this gate reads,
    # so `X-Forwarded-Host: canonical.example.com` sent to a tenant custom domain
    # would open the admin console. That weakness is project-wide (#4024) and is
    # not fixable here; this gate declines to rely on it.
    #
    # THE RULE (#host_provenance_trusted?): a detected host is accepted only when
    #
    #   a. env['otto.via_trusted_proxy'] == true — the operator configured proxy
    #      trust and this peer passed it. Forwarded headers are then a fact about
    #      the operator's own proxy tier; OR
    #   b. no forwarded host header is present at all, so nothing could have
    #      overridden the Host header; OR
    #   c. one is present but the detected host EQUALS the host the Host header
    #      alone would have produced — the forwarded header did not change the
    #      answer, so there is nothing to distrust.
    #
    # Otherwise the request is DENIED. It is not silently downgraded to the
    # HTTP_HOST-derived host: in the topology this defends (Approximated-style
    # ingress with trusted_proxy unset) `Host` is the ORIGIN's own hostname —
    # the canonical one, which IS on the allowlist — while the tenant domain
    # rides in Apx-Incoming-Host. Falling back to Host would therefore ADMIT
    # every tenant-domain request, the exact inverse of this feature. Denying is
    # the only reading that fails closed. The tryout at
    # "HTTP_HOST naming a DENIED host does not evict an allowed detected host"
    # pins the other half: HTTP_HOST is never an input, only a corroborator.
    #
    # Cost, stated plainly: a deployment behind a proxy that rewrites the Host
    # header to an internal name AND forwards the public one in a header, with
    # site.network.trusted_proxy unset, now 404s both admin surfaces. The two
    # remedies are in the WARN — configure site.network.trusted_proxy (correct
    # for every other gate in the stack too), or ADMIN_ALLOWED_HOSTS=*.
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
    #     entry survives): this middleware DENIES both surfaces, and
    #     Onetime::Config.check_admin_allowed_hosts explains why at boot. Going
    #     inert here would serve the admin console on every host from a config
    #     whose plain intent was to restrict it — failing open on a typo. `*`
    #     remains the way to turn the gate off.
    #
    #   THE CONFIG COULD NOT BE READ AT ALL (OT.conf raised): treated as the
    #     second case, never the first. "Unset" and "unreadable" are different
    #     facts and collapsing them would degrade a configured gate to the
    #     anchor fallback and then to INACTIVE — admin on every hostname,
    #     announced by a boot WARN blaming site.host.
    #
    # ## Client IP resolution
    #
    # The allowlist check MUST use the trusted-proxy-resolved client IP, never a
    # raw forwarding header, or the allowlist is trivially spoofable by sending
    # `X-Forwarded-For: <an-allowed-ip>`. Membership is judged through
    # env['otto.ip_match'] — the verdict-only closure the universal
    # IPPrivacyMiddleware mount installs over the resolved, PRE-MASK client IP
    # (configured from site.network.trusted_proxy via
    # MiddlewareStack.ip_privacy_security_config) — because the canonical
    # env['otto.client_ip'] is privacy-MASKED before this middleware runs: the
    # last IPv4 octet (IPv6: the last 80 bits) is zeroed at the default
    # precision. Matching the masked value misjudges every range finer than the
    # mask in both directions — a single-admin-IP /32 entry can never match its
    # own client, while an entry that happens to equal a masked network address
    # admits every neighbor that shares it. The closure answers at full
    # /32–/128 precision without the unmasked address ever landing in env, a
    # log, or this middleware; it resolves via the same
    # Otto::Utils.resolve_client_ip the auth strategies use, so the network
    # gate still agrees with ban checks, sessions, and audit attribution on WHO
    # the client is. A request that never passed the otto mount has no closure;
    # membership then falls back to comparing the resolved IP itself, and that
    # same mount is what writes env['otto.client_ip'], so with it absent
    # #resolve_client_ip re-resolves the unmasked address. The closure and the
    # canonical IP are co-written by that one middleware: an env that sets
    # otto.client_ip by hand without running it is out of contract, and the
    # fallback would judge whatever masked value it was handed. When no client
    # IP can be resolved and an allowlist is configured, the request is denied
    # (404) — fail closed; the closure answers false for a request with no
    # resolvable IP.
    #
    # ## Path matching
    #
    # This middleware runs INSIDE each app, after Rack::URLMap has stripped the
    # mount prefix into SCRIPT_NAME. The colonel API app is mounted at
    # `/api/colonel` (PATH_INFO becomes `/info`, `/stats`, …) and the core web
    # app at `/` (PATH_INFO stays `/colonel`). We reconstruct the full request
    # path from SCRIPT_NAME + PATH_INFO so both surfaces match regardless of
    # which app is handling the request, and NORMALIZE it exactly the way the
    # Otto router does before dispatch (Otto::Utils.normalize_path) — see
    # #request_path.
    #
    # The HTML denial body, kept OUTSIDE the class it belongs to only because a
    # 37-line literal inside it eats a third of the Metrics/ClassLength budget
    # that the gate's reasoning needs. Deliberately plain and generic: it must
    # look like an ordinary not-found page, never like a guard announcing
    # itself. Rendered once at load (the file is frozen_string_literal).
    ADMIN_NOT_FOUND_HTML = <<~HTML
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

    class AdminNetworkIsolation
      # The surfaces this middleware guards. Named in every boot log so an
      # operator can grep for what is (and is not) gated.
      SURFACES = %w[/colonel /api/colonel].freeze

      # @see Onetime::Middleware::ADMIN_NOT_FOUND_HTML
      NOT_FOUND_HTML = ADMIN_NOT_FOUND_HTML

      # Returned by #site_admin_list when the config could not be READ, as
      # opposed to having been left unset. A Symbol, so it can never collide
      # with a value that came out of YAML or ENV. See #site_admin_list.
      CONFIG_UNREADABLE = :__admin_config_unreadable__

      # Rack env keys for the host headers Rack::DetectHost will honor from a
      # trusted peer. Derived from ITS list, never a local copy: a header added
      # there is a header this gate must distrust from an untrusted peer.
      FORWARDED_HOST_ENV_KEYS = Rack::DetectHost::FORWARDED_HEADERS.map do |header|
        "HTTP_#{header.tr('-', '_').upcase}"
      end.freeze

      # Path used when the request path cannot be normalized at all. Fails
      # CLOSED: an unparseable path is judged as an admin surface, so a
      # normalization failure can never be a way past the gates.
      UNPARSEABLE_PATH = '/colonel'

      class << self
        # Boot logging is per-DEPLOYMENT, but this middleware is constructed
        # once per mounted application (13 of them). Without a ledger every
        # boot prints 13 identical posture lines — and 13 copies of any WARN
        # saying the admin surfaces are unprotected or dark, which reads like
        # 13 separate misconfigurations.
        #
        # Keyed by [tag, payload] rather than tag alone: the 13 mounts share
        # one config and collapse to one line, while a genuinely DIFFERENT
        # posture (a second Rack app built from other config, which only
        # happens in tests and embeddings) still gets its own line instead of
        # being silently swallowed. Sibling of
        # Onetime::Application::MiddlewareStack.warn_once, which cannot be
        # reused here: it takes a String and these carry structured payloads
        # the operator docs quote field by field.
        #
        # @param tag [Symbol] dedupe key
        # @param payload [Hash] structured log payload, part of the key
        # @return [void]
        def log_once(tag, payload)
          @announced ||= {}
          key          = [tag, payload]
          return if @announced.key?(key)

          @announced[key] = true
          yield
        end

        # Clear the ledger. Tests only — a process that has booted has no
        # reason to re-announce its posture.
        #
        # Wired to run BEFORE EVERY EXAMPLE in spec/spec_helper.rb, not left to
        # each spec to remember. The ledger is process-wide and a test process
        # builds many stacks: uncleared, the first example to produce a given
        # posture is the only one that can observe its boot line, and every
        # later assertion about one silently sees nothing. try/unit/middleware/
        # admin_network_isolation_try.rb calls it explicitly instead — tryouts
        # have no per-case hook, and its ledger cases count announcements, so
        # they need the reset at a point they choose.
        #
        # @return [void]
        def reset_boot_announcements!
          @announced = {}
        end

        # How many distinct boot announcements this process has emitted.
        # Specs only; the dedupe is otherwise invisible.
        #
        # @return [Integer]
        def boot_announcement_count
          (@announced || {}).size
        end
      end

      def initialize(app)
        @app                = app
        @logger             = Onetime.get_logger('AdminNetworkIsolation')
        @config_read_errors = {}

        # Both allowlists are resolved ONCE, here — the process has booted and
        # nothing re-reads config per request. EACH gate carries its own active
        # flag rather than deriving one from emptiness: an ACTIVE gate with an
        # EMPTY allowlist is the fail-closed backstop for a list that was
        # configured but yielded nothing, and "inactive" must not be reachable
        # by accident.
        @allowed_ranges, @network_gate = resolve_network_gate
        @allowed_hosts,  @host_gate    = resolve_host_gate

        log_boot_posture
      end

      def call(env)
        # Cheapest discriminator first, and it is this one: with both gates
        # inactive — the pre-#4062 self-hosted default — the middleware is a
        # strict NO-OP that allocates nothing, and the two app-layer auth
        # layers are the sole gate. Reconstructing the path first would put a
        # String allocation on every request of every mounted app to answer a
        # question two already-computed booleans settle.
        return @app.call(env) unless host_gate_active? || network_gate_active?

        full_path = request_path(env)
        return @app.call(env) unless admin_surface?(full_path)

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
        @network_gate
      end

      # Host gate. Fails closed twice over: an active gate with an unresolvable
      # (nil or empty) detected host denies, mirroring the nil-IP path in
      # #allowed?, and so does one whose detected host cannot be attributed to
      # a trusted peer (see #host_provenance_trusted?).
      #
      # The three host denials WARN distinctly — from each other and from the
      # network one, four lines in total — so operators can tell the refusals
      # apart in logs; the allowlist is never echoed into the response, only
      # into the log.
      def host_denied?(env, full_path)
        return false unless host_gate_active?

        host = detected_host(env)

        # Provenance BEFORE membership: a host we cannot attribute is denied
        # even when it is on the allowlist — being on the allowlist is exactly
        # what an attacker who can set a forwarded header would arrange.
        unless host_provenance_trusted?(env, host)
          @logger.warn 'Admin surface access denied: forwarded host from an untrusted peer',
            {
              host: host,
              path: full_path,
              method: env['REQUEST_METHOD'],
              note: 'a forwarded host header changed the detected host, but the peer is not a configured ' \
                    'trusted proxy. Set site.network.trusted_proxy with explicit proxy CIDRs — filter mode ' \
                    'with none listed trusts every private peer — or ADMIN_ALLOWED_HOSTS=* to turn the gate off',
            }

          return true
        end

        # THERE IS NO HOST TO JUDGE — same 404, its own line. Routing this into
        # the membership WARN below would tell the operator their host was
        # rejected BY THE ALLOWLIST, when the allowlist was never consulted and
        # `host` logged as nil. See #warn_unresolvable_host.
        return warn_unresolvable_host(env, full_path, host) if host.nil? || host.empty?

        return false if host_allowed?(host)

        @logger.warn 'Admin surface access denied by host allowlist',
          {
            host: host,
            path: full_path,
            method: env['REQUEST_METHOD'],
          }

        true
      end

      # The third refusal: the gate is ACTIVE and Rack::DetectHost emitted
      # nothing to compare against the allowlist.
      #
      # The behavior is identical to the other two (404, fail closed); only the
      # diagnosis differs, and the diagnosis is the entire reason this exists.
      # The shape that produces it in the field: a single-container install
      # reached by bare IP whose operator set ADMIN_ALLOWED_HOSTS=10.0.0.5 — an
      # IP literal, which DetectHost never emits and AdminHostAllowlist
      # therefore never admits. That list is unenforceable, so the gate is
      # active with an empty allowlist, the detected host is nil on EVERY
      # request, and both surfaces 404 forever. Reported as an allowlist
      # rejection it points the operator at site.admin.allowed_hosts, where
      # nothing they can write will help.
      #
      # @return [true] always; the caller returns it as the denial.
      def warn_unresolvable_host(env, full_path, host)
        @logger.warn 'Admin surface access denied: no host could be detected for this request',
          {
            host: host,
            path: full_path,
            method: env['REQUEST_METHOD'],
            note: 'Rack::DetectHost emits no host for a bare-IP `Host:` header, localhost forms, or a ' \
                  'malformed name, so site.admin.allowed_hosts was never consulted. Behind a proxy, forward ' \
                  'the original Host (`proxy_set_header Host $host;`, plus site.network.trusted_proxy for ' \
                  'forwarded hosts); otherwise use a routable hostname, or ADMIN_ALLOWED_HOSTS=* to turn it off',
          }

        true
      end

      # Whether the detected host can be attributed to something better than a
      # client-supplied forwarded header. See the class doc ("Forwarded-host
      # provenance") for the threat this closes and why the answer is DENY
      # rather than a fall back to HTTP_HOST.
      #
      # @param env [Hash] the Rack env
      # @param host [String, nil] the normalized detected host
      # @return [Boolean]
      def host_provenance_trusted?(env, host)
        # (a) Operator-configured proxy trust, and this peer passed it. The key
        # is TRI-STATE (otto#228): written only when trust is configured, so
        # `== true` — never `!= false` — is the grant-only read.
        return true if env[Rack::DetectHost::VIA_TRUSTED_PROXY_KEY] == true

        # There is no host to attribute, so there is nothing to distrust: a
        # forwarded header that produced NO host overrode nothing. Not a
        # provenance question, and deliberately not answered as one — the
        # caller denies it immediately afterwards through
        # #warn_unresolvable_host, whose line names the real cause (no host was
        # detected) instead of blaming a proxy the operator may not have.
        return true if host.nil? || host.empty?

        # (b) Nothing that could have overridden the Host header is present.
        return true unless forwarded_host_header?(env)

        # (c) A forwarded header is present but did not change the answer: the
        # detected host is what the Host header alone would have produced.
        # Both sides go through DetectHost's OWN extraction before ours, so
        # this compares what DetectHost compared.
        host == host_header_host(env)
      end

      # Whether the request carries any host header DetectHost would honor from
      # a trusted peer. Presence only — the VALUE is never read here.
      def forwarded_host_header?(env)
        FORWARDED_HOST_ENV_KEYS.any? { |key| env.key?(key) }
      end

      # The host the `Host:` header alone would have produced, normalized
      # identically to the detected host. A CORROBORATOR, never an input: it is
      # only ever compared against the detected host, never matched against the
      # allowlist. See the tryout "HTTP_HOST alone (no detected host at all)
      # fails closed".
      def host_header_host(env)
        normalize_host(Rack::DetectHost.normalize_host(env['HTTP_HOST']))
      end

      # Network (CIDR) gate. Whether it counts as ACTIVE at all is decided once,
      # at construction — see #resolve_network_gate.
      def network_denied?(env, full_path)
        return false unless network_gate_active?

        return false if network_allowed?(env)

        # The masked/resolved IP, not the pre-mask one: the closure never
        # discloses the address it judged, and the denial line must not either.
        @logger.warn 'Admin surface access denied by network isolation',
          {
            ip: resolve_client_ip(env),
            path: full_path,
            method: env['REQUEST_METHOD'],
          }

        true
      end

      # Allowlist membership at full precision when the request came through
      # the otto mount, at the resolved value otherwise.
      #
      # env['otto.ip_match'] is the verdict-only closure IPPrivacyMiddleware
      # installs over the resolved PRE-MASK client IP. It is consulted first
      # because env['otto.client_ip'] is already privacy-masked here, and a
      # masked address misjudges any range finer than the mask (see the class
      # doc, "Client IP resolution"). @allowed_ranges is handed over as the
      # pre-parsed IPAddr list, so a malformed configured entry — dropped, with
      # a WARN, at construction — can never make the closure raise. The closure
      # answers false when the request had no resolvable IP: fail closed.
      #
      # A request that never passed IPPrivacyMiddleware (embeddings, bare-Rack
      # tests) carries no closure — anything non-callable in the key is judged
      # the same way, never called. #allowed? then compares the resolved IP
      # itself, and that same topology leaves env['otto.client_ip'] unset, so
      # #resolve_client_ip re-resolves the unmasked address. The two keys are
      # co-written by that one middleware: an env that sets otto.client_ip by
      # hand without running it is out of contract, and the fallback would
      # judge whatever masked value it was handed.
      def network_allowed?(env)
        matcher = env['otto.ip_match']
        matcher.respond_to?(:call) ? matcher.call(@allowed_ranges) : allowed?(resolve_client_ip(env))
      end

      # Full request path independent of where the app is mounted, canonicalized
      # the way the Otto router canonicalizes before dispatch. Rack::URLMap
      # moves the mount prefix into SCRIPT_NAME, so PATH_INFO alone would be
      # `/info` inside the colonel API app (mounted at /api/colonel).
      #
      # NORMALIZATION IS SECURITY-LOAD-BEARING, not tidiness. The router
      # dispatches on Otto::Utils.normalize_path, which percent-decodes: it
      # serves `GET /%63olonel` and `/colonel%2Fsettings` as the admin routes.
      # Matching the RAW string here would let both spellings miss
      # #colonel_shell?, skip BOTH gates, and then be routed to the admin
      # console anyway. Same idiom, and the same reasoning, as
      # HealthAccessControl#health_endpoint? and SessionSkip#skip?.
      #
      # Otto::Utils.normalize_path documents that it does not raise (it catches
      # ArgumentError from Rack::Utils.unescape and scrubs invalid bytes) and
      # always returns a String. The rescue is for a future in which that stops
      # being true: a path we cannot canonicalize is treated as an admin
      # surface, so the failure mode is a denial, never a bypass.
      def request_path(env)
        Otto::Utils.normalize_path("#{env['SCRIPT_NAME']}#{env['PATH_INFO']}")
      rescue StandardError => ex
        @logger.warn 'Admin surface path normalization failed; judging it as an admin surface',
          { error: "#{ex.class}: #{ex.message}" }

        UNPARSEABLE_PATH
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

      # Membership of ONE resolved IP in the parsed ranges. The no-closure
      # fallback for #network_allowed?: in a full stack env['otto.client_ip']
      # is the privacy-masked address, so ranges finer than the mask must go
      # through the closure, never through here. Nil/empty/malformed all fail
      # closed.
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
      #
      # RETURNS A SENTINEL, NOT nil, ON FAILURE. nil is indistinguishable from
      # "the operator did not configure this", and that collision is a security
      # bug: a raising or not-yet-populated OT.conf would silently degrade a
      # CONFIGURED host gate to the canonical-anchor fallback, and from there to
      # INACTIVE on any install whose anchors are unroutable — admin served on
      # every hostname, announced by a boot WARN blaming site.host. The
      # exception is kept so the eventual log names the real cause instead of
      # the innocent bystander.
      def site_admin_list(key)
        OT.conf.dig('site', 'admin', key)
      rescue StandardError => ex
        @config_read_errors[key] = "#{ex.class}: #{ex.message}"
        CONFIG_UNREADABLE
      end

      def unreadable?(value)
        value.equal?(CONFIG_UNREADABLE)
      end

      # Resolve the NETWORK gate once at construction.
      #
      # @return [Array(Array<IPAddr>, Boolean)] the ranges, and whether the gate
      #   is active. Empty/unset config leaves it INACTIVE (the self-hosted
      #   default, unchanged). A configured list that yields no usable range is
      #   ACTIVE and denying — see #unusable_network_gate.
      def resolve_network_gate
        configured = configured_cidrs
        return unreadable_network_gate if unreadable?(configured)

        entries = Array(configured).map { |cidr| cidr.to_s.strip }.reject(&:empty?)
        return [[], false] if entries.empty?

        ranges = parse_allowed_cidrs(entries)
        return [ranges, true] if ranges.any?

        unusable_network_gate(entries)
      end

      # An operator wrote a CIDR list and not one entry parsed (`100.64.0.0\10`,
      # a comma that survived splitting, a hostname). Deactivating the gate
      # here would leave every WARNed-away entry an empty range set, emptiness
      # reading as "inactive", and the admin surfaces silently reachable from
      # anywhere while the operator believed a VPN restriction was in force.
      # Same rule as the host gate — a list an operator wrote is never silently
      # disabled — and the same deliberate asymmetry with an EMPTY list, which
      # still means "no network gate".
      def unusable_network_gate(entries)
        log_once(:cidrs_unusable, { entries: entries }) do
          @logger.error 'Admin CIDR allowlist has no usable range; denying both admin surfaces',
            {
              entries: entries,
              surfaces: SURFACES,
              note: '/colonel and /api/colonel are returning 404 to EVERY request because no entry in ' \
                    'site.admin.allowed_cidrs parses as a CIDR range. Fix the entries ' \
                    '(ADMIN_ALLOWED_CIDRS=100.64.0.0/10,10.0.0.0/8) or unset it entirely to leave the ' \
                    'network gate off',
            }
        end

        [[], true]
      end

      # OT.conf raised while reading site.admin.allowed_cidrs. ACTIVE and
      # denying: see #site_admin_list for why this is not treated as "unset".
      def unreadable_network_gate
        log_once(:cidrs_unreadable, { error: @config_read_errors['allowed_cidrs'] }) do
          @logger.error 'Cannot read site.admin.allowed_cidrs; denying both admin surfaces',
            {
              error: @config_read_errors['allowed_cidrs'],
              surfaces: SURFACES,
              note: 'the config could not be READ (this is not an unset value), so both admin gates ' \
                    'fail closed and /colonel and /api/colonel return 404 to EVERY request',
            }
        end

        [[], true]
      end

      def parse_allowed_cidrs(value)
        Array(value).filter_map do |cidr|
          next if cidr.to_s.strip.empty?

          IPAddr.new(cidr.to_s.strip)
        rescue IPAddr::InvalidAddressError
          log_once(:cidr_invalid, { cidr: cidr.to_s }) do
            @logger.warn "Invalid CIDR in site.admin.allowed_cidrs, skipping: #{cidr}"
          end
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
        raw = configured_hosts
        return unreadable_host_gate if unreadable?(raw)

        configured = Onetime::Utils::AdminHostAllowlist.classify(raw)

        return anchor_host_gate if configured.empty?

        # `*` ANYWHERE in the list turns the gate off, not just as the sole
        # entry. It is the documented escape hatch and the remedy every
        # diagnostic in this file recommends; a sibling entry does not make it
        # ambiguous, it just makes the sibling inert (and named in a WARN).
        return wildcard_host_gate(configured) if configured.wildcard

        configured_host_gate(configured)
      end

      # OT.conf raised while reading site.admin.allowed_hosts. ACTIVE and
      # denying: see #site_admin_list for why this is not treated as "unset".
      def unreadable_host_gate
        log_once(:hosts_unreadable, { error: @config_read_errors['allowed_hosts'] }) do
          @logger.error 'Cannot read site.admin.allowed_hosts; denying both admin surfaces',
            {
              error: @config_read_errors['allowed_hosts'],
              surfaces: SURFACES,
              note: 'the config could not be READ (this is not an unset value), so the host gate fails ' \
                    'closed and /colonel and /api/colonel return 404 to EVERY request',
            }
        end

        [[], true]
      end

      # An operator wrote a list. Enforce whatever survived classification.
      def configured_host_gate(classified)
        warn_rejected_entries(classified.rejected)

        return [classified.hosts, true] if classified.hosts.any?

        # THE RUNTIME HALF of the same judgment Onetime::Config
        # .check_admin_allowed_hosts warns about at boot. An explicit allowlist
        # with nothing enforceable must DENY, never disable itself: the
        # operator's plain intent was to restrict, and `*` is how you ask for
        # the opposite. This is also why that boot check does not have to abort
        # the process (see it) — the over-exposure it exists to prevent is
        # already impossible by the time a request arrives.
        #
        # An operator reading this line is debugging an outage, not auditing an
        # invariant: lead with what is happening to the surfaces, then the
        # cause, then the remedy.
        log_once(:hosts_unenforceable, { entries: classified.rejected.map(&:first) }) do
          @logger.warn 'Admin host allowlist has no enforceable entry; denying both admin surfaces',
            {
              entries: classified.rejected.map(&:first),
              surfaces: SURFACES,
              note: '/colonel and /api/colonel are returning 404 to EVERY request because no entry in ' \
                    'site.admin.allowed_hosts can match a detected host. Set ADMIN_ALLOWED_HOSTS to a routable ' \
                    'hostname, unset it to allow the canonical host only (on localhost/bare-IP installs that ' \
                    'self-disables the gate instead), or set it to * to disable the host gate',
            }
        end

        [[], true]
      end

      # `*` is listed: the documented escape hatch. Anything beside it is inert
      # and gets named, so an operator who wrote `*,admin.example.com` learns
      # the second entry did nothing — without the gate second-guessing the
      # explicit `*`.
      def wildcard_host_gate(classified)
        log_once(:hosts_wildcard, { surfaces: SURFACES }) do
          @logger.warn 'Admin host allowlist DISABLED by `*`',
            {
              surfaces: SURFACES,
              note: 'both admin surfaces answer on every hostname the app serves; the CIDR gate is unaffected',
            }
        end

        warn_ignored_wildcard_siblings(classified) unless classified.wildcard_only?

        [[], false]
      end

      # States only what `*` did to the OTHER entries. Whether those entries
      # were themselves usable is beside the point: `*` turned the gate off, so
      # nothing is enforced either way.
      def warn_ignored_wildcard_siblings(classified)
        ignored = classified.hosts + classified.rejected.map(&:first)

        log_once(:hosts_wildcard_siblings, { entries: ignored }) do
          @logger.warn 'Ignoring every other entry in site.admin.allowed_hosts: `*` disables the host gate',
            {
              entries: ignored,
              note: 'remove the `*` to enforce the named hosts',
            }
        end
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

        log_once(:hosts_inactive, { hosts: canonical_anchor_hosts }) do
          @logger.warn 'Admin host allowlist INACTIVE: no routable hostname configured',
            {
              source: 'canonical anchors',
              hosts: canonical_anchor_hosts,
              surfaces: SURFACES,
              note: 'localhost and bare-IP hosts are never detected as a host; set ADMIN_ALLOWED_HOSTS ' \
                    '(or site.host / DEFAULT_DOMAIN) to a routable hostname to enable the host gate',
            }
        end

        [[], false]
      end

      # Entries that can never match are dropped, not fatal, as long as
      # something enforceable remains. Named at boot so the operator can see
      # WHY the effective allowlist is smaller than what they wrote.
      def warn_rejected_entries(rejected)
        return if rejected.empty?

        described = Onetime::Utils::AdminHostAllowlist.describe_rejections(rejected)

        log_once(:hosts_rejected, { entries: described }) do
          @logger.warn 'Ignoring unusable entries in site.admin.allowed_hosts',
            {
              entries: described,
            }
        end
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

      # Admit the `www.` SIBLING of each anchor, in both directions: a bare
      # anchor also admits `www.<anchor>`, and a `www.` anchor also admits the
      # name with the prefix removed. Neither CanonicalHosts nor DomainParser
      # synthesizes either form, so it is done here.
      #
      # THIS IS NOT DomainStrategy::Chooserator.equal_to? AND MUST NOT BE
      # "ALIGNED" WITH IT.
      # That predicate resolves the REGISTRABLE DOMAIN first, so for an anchor
      # `app.example.com` it admits `www.example.com` — a different site — and
      # never admits an apex when the anchor is a www host. This method is
      # purely lexical: `app.example.com` yields `www.app.example.com`, and
      # `www.example.com` yields `example.com`. Substituting one for the other
      # silently changes WHICH HOSTS SERVE /colonel in both directions. The
      # behavior here is pinned by tryouts on purpose; change the tryouts first
      # if it should ever differ.
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

      # Emit a boot log line at most once per process for a given [tag,
      # payload]. Delegates to the class-level ledger; see .log_once for why
      # this middleware needs one at all (13 mounted apps, one deployment).
      #
      # Names the class EXPLICITLY rather than going through `self.class`: a
      # subclass (try/unit/middleware's TestAdminNetworkIsolation, or any
      # embedding that wraps this) would otherwise get a ledger of its own and
      # the guarantee would silently become once-per-CLASS.
      def log_once(tag, payload, &)
        AdminNetworkIsolation.log_once(tag, payload, &)
      end

      # One INFO line per process describing the effective posture of BOTH
      # factors, including when a gate is off — so "off" is distinguishable
      # from "misconfigured" without diffing config against source.
      #
      # ONCE PER PROCESS, NOT ONCE PER MOUNT. MiddlewareStack.configure runs for
      # each of the 13 registered applications, all from the same config;
      # without the ledger this line (and every WARN above it) would appear 13
      # times per boot, which reads like 13 separate deployments' worth of
      # misconfiguration.
      #
      # `trusted_proxy` is on this line, and deliberately not on one of its own:
      # it qualifies the two gate states beside it. Both gates judge inputs that
      # a proxy layer determines (the detected host; the resolved client IP), so
      # `host_gate: active` correlated with `trusted_proxy: disabled` is the
      # whole point — see #trusted_proxy_posture.
      def log_boot_posture
        posture = {
          host_gate: host_gate_active? ? 'active' : 'inactive',
          allowed_hosts: @allowed_hosts,
          network_gate: network_gate_active? ? 'active' : 'inactive',
          allowed_cidrs: effective_cidrs,
          trusted_proxy: trusted_proxy_posture,
          surfaces: SURFACES,
        }

        log_once(:posture, posture) do
          @logger.info 'Admin surface isolation posture', posture
        end
      end

      # The parsed ranges as an operator would have written them. IPAddr#to_s
      # drops the mask, so a configured 100.64.0.0/10 would otherwise log as
      # `100.64.0.0` — a /10 rendered as what looks like a single host, on the
      # one line an operator reads to confirm the posture took effect.
      def effective_cidrs
        @allowed_ranges.map { |range| "#{range}/#{range.prefix}" }
      end

      # Whether the deployment declares a trusted reverse proxy, and in which
      # mode. Both halves are read through the SAME accessors that decide how
      # the universal IP-privacy mount is configured
      # (Onetime::Application::MiddlewareStack.trusted_proxy_enabled? and
      # .trusted_proxy_mode, consumed by .ip_privacy_security_config), so this
      # line cannot report a posture the stack does not actually have. In
      # particular the mode is the CANONICALIZED, VALIDATED one — a deployment
      # configured `TRUSTED_PROXY_MODE=Depth` reports `mode=depth`, and one
      # configured with a typo reports `mode=filter` (the mode it is really
      # running) alongside the accessor's own boot warning, rather than echoing
      # the operator's raw string back at them (#4087).
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
        stack = Onetime::Application::MiddlewareStack
        return 'disabled' unless stack.trusted_proxy_enabled?

        "enabled (mode=#{stack.trusted_proxy_mode})"
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
            [NOT_FOUND_HTML],
          ]
        end
      end
    end
  end
end
