# try/unit/middleware/admin_network_isolation_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Middleware::AdminNetworkIsolation
#
# This middleware guards the Colonel admin surfaces (/colonel shell +
# /api/colonel API) with TWO INDEPENDENT gates. A request must pass every gate
# that is ACTIVE; failing either produces the SAME 404
# (indistinguishable-from-absent, NOT 403). When both gates are inactive the
# middleware is a strict no-op.
#
#   HOST    (#4062, site.admin.allowed_hosts) — ACTIVE BY DEFAULT. An empty
#           list falls back to the canonical ANCHOR hosts
#           (features.domains.default + site.host, NOT the link_domains pool)
#           plus their www. variants. `*` is the escape hatch. The ANCHOR
#           fallback self-disables when no anchor is a hostname
#           Rack::DetectHost could ever emit (localhost / bare IP), so stock
#           local-dev is unaffected. An EXPLICIT list with nothing enforceable
#           in it does the OPPOSITE: it denies (see below). The host comes from
#           env[Rack::DetectHost.result_field_name] — never HTTP_HOST, never
#           env['onetime.domain_strategy'].
#
#   NETWORK (site.admin.allowed_cidrs) — OPT-IN. Client IP is resolved from the
#           trusted-proxy-aware env['otto.client_ip'], so a raw X-Forwarded-For
#           header cannot bypass it.
#
# THE INERT/DENY ASYMMETRY, since it is the one thing most likely to be
# "harmonized" by a later reader:
#
#   allowed_hosts UNSET + unroutable anchors  -> gate INERT (nobody configured
#     anything; a fail-closed default would 404 /colonel on every stock
#     single-container install).
#   allowed_hosts SET to unenforceable values -> gate ACTIVE with an EMPTY
#     allowlist, i.e. DENY BOTH SURFACES. Onetime::Config
#     .validate_admin_allowed_hosts! normally refuses that config at boot; this
#     is the middleware's backstop for an embedding that builds a Rack app
#     without Config.raise_concerns. Going inert there would serve the admin
#     console on every host from a config whose plain intent was to restrict
#     it — failing open on a typo.
#
# Test categories:
#   1. Path matching (colonel_shell? / colonel_api?), full-path reconstruction
#   2. No-op when both allowlists are empty/unset
#   3. Outside CIDR allowlist -> 404 on both surfaces
#   4. Inside CIDR allowlist -> pass-through to auth layers
#   5. Spoofed X-Forwarded-For cannot bypass
#   6. Host gate: match/miss, normalization, nil host, `*`, literal entries
#   7. Host gate: canonical anchor fallback, link_domains pool exclusion
#   8. Host gate: the inert rule (anchors) vs the fail-closed backstop (explicit)
#   9. Host input provenance: detected host only, not HTTP_HOST / domain_strategy
#  10. Both gates together, and the identical shape of the two denials

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'rack/mock'
require 'json'
require_relative '../../../lib/onetime/middleware/admin_network_isolation'

# Test subclass to expose private predicates plus the resolved host allowlist
# (the single most useful thing to assert directly — it is computed once in
# #initialize and drives every host decision).
#
# `normalize_host` is a thin private DELEGATOR to
# Onetime::Utils::AdminHostAllowlist (which is also what
# Onetime::Config.validate_admin_allowed_hosts! uses, so the two cannot
# drift). It is exposed here because #detected_host calls it on EVERY request
# an active host gate judges: when it briefly went missing during the #4062
# refactor, both admin surfaces raised NoMethodError instead of answering, and
# nothing caught it because the default test config leaves the gate inert.
class TestAdminNetworkIsolation < Onetime::Middleware::AdminNetworkIsolation
  public :admin_surface?, :colonel_shell?, :colonel_api?, :request_path, :allowed?,
    :host_gate_active?, :network_gate_active?, :host_allowed?, :normalize_host, :detected_host

  def allowed_hosts
    @allowed_hosts
  end
end

@allowlist = Onetime::Utils::AdminHostAllowlist

# Mock app that returns 200 OK — stands in for the downstream auth layers.
@mock_app = ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }

# Config this file mutates, captured BEFORE the first write. `rake try:unit`
# runs every unit tryout in ONE process, so a leaked site.host or
# features.domains.default would silently change what later files see.
# Rack::DetectHost.result_field_name is process-global and mutable too.
@orig_admin          = OT.conf.dig('site', 'admin')&.dup
@orig_site_host      = OT.conf.dig('site', 'host')
@orig_domains        = OT.conf.dig('features', 'domains')&.dup
@orig_detected_field = Rack::DetectHost.result_field_name

# Set the CIDR allowlist in config, then build a middleware instance that reads
# it. site.host stays at the spec/config.test.yaml value (an IP literal), so
# the host gate is inert and the network gate is the sole decider.
def set_allowlist(cidrs)
  OT.conf['site'] ||= {}
  OT.conf['site']['admin'] ||= {}
  OT.conf['site']['admin']['allowed_hosts'] = []
  OT.conf['site']['admin']['allowed_cidrs'] = cidrs
  TestAdminNetworkIsolation.new(@mock_app)
end

# Write EVERY input the host gate reads, then return a fresh instance.
#
# Both allowlists are resolved once in #initialize, so a config write without a
# rebuild is invisible to an existing instance. The site_host default mirrors
# spec/config.test.yaml (an IP literal -> the anchor fallback is unenforceable
# -> the host gate is INERT), which is exactly why the ~22 existing colonel
# suites stayed green when #4062 landed.
def build_mw(hosts: [], cidrs: [], site_host: '127.0.0.1:3000', default_domain: nil, link_domains: nil)
  OT.conf['site'] ||= {}
  OT.conf['site']['admin'] ||= {}
  OT.conf['site']['admin']['allowed_hosts'] = hosts
  OT.conf['site']['admin']['allowed_cidrs'] = cidrs
  OT.conf['site']['host'] = site_host
  OT.conf['features'] ||= {}
  OT.conf['features']['domains'] ||= {}
  OT.conf['features']['domains']['default'] = default_domain
  OT.conf['features']['domains']['link_domains'] = link_domains
  TestAdminNetworkIsolation.new(@mock_app)
end

# Build a Rack env for a full path, injecting the resolved (otto) client IP and
# the validated host Rack::DetectHost writes.
# script_name simulates Rack::URLMap mounting (colonel API is mounted at
# /api/colonel, so PATH_INFO is stripped to e.g. /info).
#
# detected_host: :unset leaves the env key ABSENT (a request that never passed
# through Rack::DetectHost); nil writes an explicit nil (DetectHost ran and
# found no valid host). Both must fail closed, and they are different envs.
def admin_env(script_name:, path_info:, client_ip: nil, xff: nil, detected_host: :unset, http_host: nil,
              domain_strategy: nil)
  env = Rack::MockRequest.env_for("http://example.com#{script_name}#{path_info}")
  env['SCRIPT_NAME'] = script_name
  env['PATH_INFO'] = path_info
  env['otto.client_ip'] = client_ip if client_ip
  env['HTTP_X_FORWARDED_FOR'] = xff if xff
  env['HTTP_HOST'] = http_host if http_host
  env['onetime.domain_strategy'] = domain_strategy if domain_strategy
  env[Rack::DetectHost.result_field_name] = detected_host unless detected_host == :unset
  env
end

# Status of one admin-surface request. Defaults to the /colonel shell from a
# public IP; pass script_name/path_info for the API surface.
def status_for(mw, detected_host, script_name: '', path_info: '/colonel', client_ip: '203.0.113.9')
  env = admin_env(
    script_name: script_name,
    path_info: path_info,
    client_ip: client_ip,
    detected_host: detected_host,
  )
  mw.call(env).first
end

# Both surfaces at once: [shell_status, api_status]. Most host-gate rules are
# surface-independent and asserting one surface only would miss a path-matching
# regression on the other.
def both_surfaces(mw, detected_host, client_ip: '203.0.113.9')
  [
    status_for(mw, detected_host, client_ip: client_ip),
    status_for(mw, detected_host, script_name: '/api/colonel', path_info: '/info', client_ip: client_ip),
  ]
end

# The full response triple, with the body collapsed to a comparable String.
# Used to prove a host denial and a network denial are byte-identical.
def denial_triple(mw, detected_host, client_ip, script_name, path_info)
  status, headers, body = mw.call(
    admin_env(
      script_name: script_name,
      path_info: path_info,
      client_ip: client_ip,
      detected_host: detected_host,
    ),
  )
  [status, headers, body.join]
end

# =================================================================
# Path matching + full-path reconstruction
# =================================================================

@mw = set_allowlist(['10.0.0.0/8'])

## colonel_shell? - matches exact /colonel
@mw.colonel_shell?('/colonel')
#=> true

## colonel_shell? - matches /colonel/ subpath
@mw.colonel_shell?('/colonel/customers')
#=> true

## colonel_shell? - does NOT match /colonels (prefix only)
@mw.colonel_shell?('/colonels')
#=> false

## colonel_api? - matches exact /api/colonel
@mw.colonel_api?('/api/colonel')
#=> true

## colonel_api? - matches /api/colonel/ subpath
@mw.colonel_api?('/api/colonel/users')
#=> true

## colonel_api? - does NOT match /api/colonelish
@mw.colonel_api?('/api/colonelish')
#=> false

## admin_surface? - false for unrelated path
@mw.admin_surface?('/dashboard')
#=> false

## request_path - reconstructs full path from SCRIPT_NAME + PATH_INFO (mounted API app)
@mw.request_path('SCRIPT_NAME' => '/api/colonel', 'PATH_INFO' => '/info')
#=> '/api/colonel/info'

## request_path - core web app has empty SCRIPT_NAME, /colonel in PATH_INFO
@mw.request_path('SCRIPT_NAME' => '', 'PATH_INFO' => '/colonel')
#=> '/colonel'

# =================================================================
# allowed? - membership check against parsed ranges
# =================================================================

## allowed? - IP inside the configured range
@mw.allowed?('10.1.2.3')
#=> true

## allowed? - IP outside the configured range
@mw.allowed?('203.0.113.9')
#=> false

## allowed? - nil IP fails closed
@mw.allowed?(nil)
#=> false

## allowed? - empty IP fails closed
@mw.allowed?('')
#=> false

## allowed? - malformed IP fails closed
@mw.allowed?('not_an_ip')
#=> false

# =================================================================
# No-op when both allowlists are empty/unset (self-hosted default)
# =================================================================

## empty allowlist - /colonel from a public IP passes through (200)
@noop = set_allowlist([])
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9')
@status, _, _ = @noop.call(@env)
@status
#=> 200

## empty allowlist - /api/colonel from a public IP passes through (200)
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9')
@status, _, _ = @noop.call(@env)
@status
#=> 200

## nil allowlist - also a no-op
@nilmw = set_allowlist(nil)
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9')
@status, _, _ = @nilmw.call(@env)
@status
#=> 200

# =================================================================
# Configured: outside the allowlist -> 404 on BOTH surfaces
# =================================================================

## outside allowlist - /colonel shell returns 404 (not 403)
@iso = set_allowlist(['10.0.0.0/8', '100.64.0.0/10'])
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
@status
#=> 404

## outside allowlist - /colonel shell returns HTML content type
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
@headers['Content-Type']
#=> 'text/html; charset=utf-8'

## outside allowlist - /colonel/customers subpath returns 404
@env = admin_env(script_name: '', path_info: '/colonel/customers', client_ip: '8.8.8.8')
@status, _, _ = @iso.call(@env)
@status
#=> 404

## outside allowlist - /api/colonel returns 404
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
@status
#=> 404

## outside allowlist - /api/colonel returns JSON content type + error body
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
[@headers['Content-Type'], JSON.parse(@body.first)['error']]
#=> ['application/json', 'Not Found']

## outside allowlist - unresolvable client IP fails closed (404)
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: nil)
@env.delete('HTTP_X_FORWARDED_FOR')
@env.delete('REMOTE_ADDR')
@status, _, _ = @iso.call(@env)
@status
#=> 404

# =================================================================
# Configured: inside the allowlist -> pass through to auth layers
# =================================================================

## inside allowlist - /colonel from 10.0.0.5 passes through (200)
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '10.0.0.5')
@status, _, _ = @iso.call(@env)
@status
#=> 200

## inside allowlist - /api/colonel from Tailscale CGNAT passes through (200)
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '100.64.7.7')
@status, _, _ = @iso.call(@env)
@status
#=> 200

## configured - non-admin path passes through regardless of IP
@env = admin_env(script_name: '', path_info: '/dashboard', client_ip: '203.0.113.9')
@status, _, _ = @iso.call(@env)
@status
#=> 200

# =================================================================
# Spoofed X-Forwarded-For cannot bypass the allowlist
# =================================================================
# The middleware resolves from the trusted-proxy-aware env['otto.client_ip'],
# never the raw header. An outside client that spoofs XFF to an allowed IP is
# still denied; the resolved IP is authoritative.

## spoofed XFF - outside client with allowed-IP XFF is still denied (404)
@env = admin_env(
  script_name: '/api/colonel',
  path_info: '/info',
  client_ip: '203.0.113.9',    # trusted-proxy-resolved (real) client
  xff: '10.0.0.5',             # attacker-supplied header claiming an allowed IP
)
@status, _, _ = @iso.call(@env)
@status
#=> 404

## resolved IP is authoritative - inside client is allowed even with a public XFF
@env = admin_env(
  script_name: '',
  path_info: '/colonel',
  client_ip: '10.0.0.5',       # trusted-proxy-resolved (real) client, allowed
  xff: '203.0.113.9',          # noise header
)
@status, _, _ = @iso.call(@env)
@status
#=> 200

# =================================================================
# HOST GATE — explicit site.admin.allowed_hosts
# =================================================================
# The host is read from env[Rack::DetectHost.result_field_name] only. Every
# case below uses a PUBLIC client IP and an empty CIDR list, so the network
# gate is inactive and the host gate is the sole decider.

## explicit allowlist - matching detected host passes through (200)
@hosts = build_mw(hosts: ['admin.example.com'])
status_for(@hosts, 'admin.example.com')
#=> 200

## explicit allowlist - the host gate reports itself active
@hosts.host_gate_active?
#=> true

## explicit allowlist - the network gate stays inactive
@hosts.network_gate_active?
#=> false

## explicit allowlist - effective list is the configured entry, verbatim
@hosts.allowed_hosts
#=> ['admin.example.com']

## explicit allowlist - non-matching detected host is denied (404)
status_for(@hosts, 'tenant.example.com')
#=> 404

## explicit allowlist - denial on /colonel is HTML, same as a CIDR denial
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9',
                 detected_host: 'tenant.example.com')
@status, @headers, @body = @hosts.call(@env)
[@status, @headers['Content-Type']]
#=> [404, 'text/html; charset=utf-8']

## explicit allowlist - denial on /api/colonel is the JSON not-found body
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9',
                 detected_host: 'tenant.example.com')
@status, @headers, @body = @hosts.call(@env)
[@status, @headers['Content-Type'], JSON.parse(@body.first)['error']]
#=> [404, 'application/json', 'Not Found']

## explicit allowlist - /api/colonel on an allowed host passes through
status_for(@hosts, 'admin.example.com', script_name: '/api/colonel', path_info: '/info')
#=> 200

## explicit allowlist - a non-admin path is untouched on a denied host
status_for(@hosts, 'tenant.example.com', path_info: '/dashboard')
#=> 200

## explicit allowlist - a /colonel SUBPATH is gated too, on both surfaces
[status_for(@hosts, 'tenant.example.com', path_info: '/colonel/customers'),
 status_for(@hosts, 'tenant.example.com', script_name: '/api/colonel', path_info: '/stats')]
#=> [404, 404]

# --- normalization: DETECTED side ---------------------------------------

## detected host - uppercase matches a lowercase entry
status_for(@hosts, 'ADMIN.Example.COM')
#=> 200

## detected host - a :port is stripped before matching
status_for(@hosts, 'admin.example.com:8443')
#=> 200

## detected host - a trailing root dot is stripped before matching
status_for(@hosts, 'admin.example.com.')
#=> 200

## detected host - multiple trailing dots are stripped
status_for(@hosts, 'admin.example.com...')
#=> 200

## detected host - a scheme is stripped before matching
status_for(@hosts, 'https://admin.example.com')
#=> 200

# --- normalization: CONFIGURED side -------------------------------------

## configured entry - uppercase, scheme, port and trailing dot all normalize
@messy = build_mw(hosts: ['  HTTPS://Admin.Example.COM:8443/  ', 'other.example.com.'])
@messy.allowed_hosts
#=> ['admin.example.com', 'other.example.com']

## configured entry - a normalized entry matches the plain detected host
status_for(@messy, 'admin.example.com')
#=> 200

## configured entry - the second normalized entry matches too
status_for(@messy, 'other.example.com')
#=> 200

## configured entry - blank entries are dropped, not treated as a match-all
@blanks = build_mw(hosts: ['', '   ', 'admin.example.com'])
@blanks.allowed_hosts
#=> ['admin.example.com']

## configured entry - blanks beside a real host do not widen it
status_for(@blanks, 'tenant.example.com')
#=> 404

## configured entry - duplicates collapse
build_mw(hosts: ['admin.example.com', 'ADMIN.example.com:443']).allowed_hosts
#=> ['admin.example.com']

## normalize_host - ONE function for both sides, and it lives in the shared
## classifier so the boot validator cannot drift from it
@allowlist.normalize_host('HTTPS://Admin.Example.COM:8443/path')
#=> 'admin.example.com'

## normalize_host - the middleware DELEGATES to that one function rather than
## keeping a second copy. #detected_host calls this on every request an active
## gate judges, so a missing/renamed delegator is a NoMethodError on both admin
## surfaces, not a mismatch.
@hosts.normalize_host('HTTPS://Admin.Example.COM:8443/path')
#=> 'admin.example.com'

## detected_host - reads the env key and normalizes it, without raising
@hosts.detected_host(Rack::DetectHost.result_field_name => 'ADMIN.Example.COM:8443')
#=> 'admin.example.com'

## detected_host - an absent key is nil, not an exception
@hosts.detected_host({})
#=> nil

## REGRESSION (#4062 refactor): an ACTIVE gate judging a REAL detected host
## must answer, not raise. Both surfaces, admitted and denied host — the four
## request shapes that never occur under the inert default test config.
[status_for(@hosts, 'admin.example.com'),
 status_for(@hosts, 'tenant.example.com'),
 status_for(@hosts, 'admin.example.com', script_name: '/api/colonel', path_info: '/info'),
 status_for(@hosts, 'tenant.example.com', script_name: '/api/colonel', path_info: '/info')]
#=> [200, 404, 200, 404]

## normalize_host - trailing root dot is stripped (a legal client-supplied FQDN)
@allowlist.normalize_host('Admin.Example.COM.')
#=> 'admin.example.com'

## normalize_host - nothing usable yields nil, never an empty match-all
[@allowlist.normalize_host(nil), @allowlist.normalize_host(''), @allowlist.normalize_host('   ')]
#=> [nil, nil, nil]

# --- fail closed: no usable host ----------------------------------------

## nil detected host - fails closed (404) even though the path is legitimate
status_for(@hosts, nil)
#=> 404

## absent detected-host key - fails closed (404)
status_for(@hosts, :unset)
#=> 404

## empty detected host - fails closed (404)
status_for(@hosts, '')
#=> 404

## whitespace-only detected host - normalizes to nil and fails closed (404)
status_for(@hosts, '   ')
#=> 404

## nil detected host - both surfaces, not just the shell
both_surfaces(@hosts, nil)
#=> [404, 404]

## host_allowed? - nil and empty are rejected directly
[@hosts.host_allowed?(nil), @hosts.host_allowed?('')]
#=> [false, false]

# --- exact match only: no subdomain or suffix tolerance -----------------

## subdomain of an allowed host is NOT admitted
status_for(@hosts, 'deeper.admin.example.com')
#=> 404

## parent of an allowed host is NOT admitted
status_for(@hosts, 'example.com')
#=> 404

## suffix-lookalike host is NOT admitted
status_for(@hosts, 'evil-admin.example.com')
#=> 404

## a host that merely ENDS with an allowed host is NOT admitted
status_for(@hosts, 'admin.example.com.evil.test')
#=> 404

# --- explicit entries are LITERAL: no www. synthesis --------------------
# The www. tolerance exists for the canonical anchor fallback only. An
# operator who names admin.example.com is not asking for www.admin.example.com.

## explicit entry does NOT admit its www. sibling
status_for(@hosts, 'www.admin.example.com')
#=> 404

## explicit entry does NOT admit its www. sibling on the API surface either
status_for(@hosts, 'www.admin.example.com', script_name: '/api/colonel', path_info: '/info')
#=> 404

## explicit www. entry does NOT admit the bare host
@wwwonly = build_mw(hosts: ['www.admin.example.com'])
[@wwwonly.allowed_hosts, status_for(@wwwonly, 'admin.example.com')]
#=> [['www.admin.example.com'], 404]

## explicit www. entry admits itself
status_for(@wwwonly, 'www.admin.example.com')
#=> 200

## explicit list REPLACES the anchor fallback - the canonical host is not admitted
@replaces = build_mw(hosts: ['admin.example.com'], default_domain: 'example.com', site_host: 'example.com')
[@replaces.allowed_hosts, status_for(@replaces, 'example.com'), status_for(@replaces, 'admin.example.com')]
#=> [['admin.example.com'], 404, 200]

# =================================================================
# HOST GATE — the `*` escape hatch
# =================================================================

## `*` as the sole entry disables the host gate
@wild = build_mw(hosts: ['*'])
[@wild.allowed_hosts, @wild.host_gate_active?]
#=> [[], false]

## `*` - any host reaches the app, on both surfaces
both_surfaces(@wild, 'anything.example.test')
#=> [200, 200]

## `*` - even a nil detected host reaches the app (the gate is OFF, not open)
status_for(@wild, nil)
#=> 200

## `*` surrounded by whitespace still normalizes to the escape hatch
build_mw(hosts: ['  *  ']).host_gate_active?
#=> false

## `*` alongside blank entries is still the SOLE meaningful entry
build_mw(hosts: ['', '*']).host_gate_active?
#=> false

## `*` does NOT disable the CIDR gate - the two factors are independent
@wild_cidr = build_mw(hosts: ['*'], cidrs: ['10.0.0.0/8'])
[@wild_cidr.host_gate_active?, @wild_cidr.network_gate_active?,
 status_for(@wild_cidr, 'anything.example.test', client_ip: '10.0.0.5'),
 status_for(@wild_cidr, 'anything.example.test', client_ip: '203.0.113.9')]
#=> [false, true, 200, 404]

## `*` mixed with named hosts - the wildcard is DROPPED, names are enforced
@mixed = build_mw(hosts: ['*', 'admin.example.com'])
[@mixed.allowed_hosts, @mixed.host_gate_active?]
#=> [['admin.example.com'], true]

## `*` mixed - the named host is admitted
status_for(@mixed, 'admin.example.com')
#=> 200

## `*` mixed - everything else is still denied (fail closed on ambiguity)
status_for(@mixed, 'tenant.example.com')
#=> 404

# =================================================================
# HOST GATE — canonical ANCHOR fallback (allowed_hosts empty)
# =================================================================
# The fallback is CanonicalHosts.normalized_anchor_hosts —
# features.domains.default + site.host — plus a www. variant of each. The
# features.domains.link_domains pool is deliberately NOT a member (#4063).

## anchor fallback - both anchors and their www. variants are admitted
@anchors = build_mw(default_domain: 'example.com', site_host: 'app.example.net')
@anchors.allowed_hosts
#=> ['example.com', 'www.example.com', 'app.example.net', 'www.app.example.net']

## anchor fallback - a nil allowed_hosts behaves exactly like an empty one
build_mw(hosts: nil, default_domain: 'example.com', site_host: 'app.example.net').allowed_hosts
#=> ['example.com', 'www.example.com', 'app.example.net', 'www.app.example.net']

## anchor fallback - the primary anchor passes
status_for(@anchors, 'example.com')
#=> 200

## anchor fallback - the www. variant of the primary anchor passes
status_for(@anchors, 'www.example.com')
#=> 200

## anchor fallback - the secondary anchor (site.host) passes
status_for(@anchors, 'app.example.net')
#=> 200

## anchor fallback - the www. variant of the secondary anchor passes
status_for(@anchors, 'www.app.example.net')
#=> 200

## anchor fallback - a tenant custom domain is denied
status_for(@anchors, 'secrets.tenant.test')
#=> 404

## anchor fallback - a subdomain of the anchor is denied
status_for(@anchors, 'tenant.example.com')
#=> 404

## anchor fallback - an unknown host is denied
status_for(@anchors, 'unknown.example.org')
#=> 404

## anchor fallback - /api/colonel is gated identically
[status_for(@anchors, 'example.com', script_name: '/api/colonel', path_info: '/info'),
 status_for(@anchors, 'secrets.tenant.test', script_name: '/api/colonel', path_info: '/info')]
#=> [200, 404]

## anchor fallback - a www. anchor also admits its bare form
build_mw(default_domain: 'www.example.com', site_host: 'app.example.net').allowed_hosts
#=> ['www.example.com', 'example.com', 'app.example.net', 'www.app.example.net']

## anchor fallback - WITHOUT features.domains.default, site.host alone anchors
@sitehost_only = build_mw(default_domain: nil, site_host: 'app.example.net')
@sitehost_only.allowed_hosts
#=> ['app.example.net', 'www.app.example.net']

## anchor fallback - site.host alone: it passes, an unrelated host does not
[status_for(@sitehost_only, 'app.example.net'), status_for(@sitehost_only, 'example.com')]
#=> [200, 404]

## anchor fallback - a configured :port on site.host is stripped
build_mw(default_domain: nil, site_host: 'app.example.net:3000').allowed_hosts
#=> ['app.example.net', 'www.app.example.net']

# --- the #4063 boundary: link_domains are NOT admin hosts ---------------

## link pool - a pool member is NOT in the effective admin allowlist
@pool = build_mw(
  default_domain: 'example.com',
  site_host: 'example.com',
  link_domains: ['links.example.net', 'short.example.org'],
)
@pool.allowed_hosts
#=> ['example.com', 'www.example.com']

## link pool - the pool member IS canonical for classification (config took)
Onetime::Utils::CanonicalHosts.normalized_hosts
#=> ['example.com', 'links.example.net', 'short.example.org']

## link pool - a request on a link-pool domain is DENIED the admin surface
status_for(@pool, 'links.example.net')
#=> 404

## link pool - second pool member is denied too
status_for(@pool, 'short.example.org')
#=> 404

## link pool - a www. sibling of a pool member is denied as well
status_for(@pool, 'www.links.example.net')
#=> 404

## link pool - the anchor still passes, so the gate is active (not vacuous)
status_for(@pool, 'example.com')
#=> 200

## link pool - denial applies to /api/colonel as well
status_for(@pool, 'links.example.net', script_name: '/api/colonel', path_info: '/info')
#=> 404

# =================================================================
# HOST GATE — the INERT rule (anchor fallback only)
# =================================================================
# Rack::DetectHost never emits localhost or an IP literal, so an anchor set
# made only of those would 404 both surfaces on every local-dev and bare-IP
# install. When NOBODY configured allowed_hosts and no ANCHOR is a hostname
# DetectHost could emit, the gate self-disables.

## DetectHost never emits `localhost` — the premise of the rule
Rack::DetectHost.valid_domain_name?('localhost')
#=> false

## ...but it WOULD emit `www.localhost`, so the rule must be judged BEFORE
## www. expansion or a localhost anchor would wrongly activate the gate
Rack::DetectHost.valid_domain_name?('www.localhost')
#=> true

## localhost anchor - the gate is inert, NOT deny-everything
@localhost = build_mw(default_domain: nil, site_host: 'localhost:3000')
[@localhost.allowed_hosts, @localhost.host_gate_active?]
#=> [[], false]

## localhost anchor - /colonel stays reachable on stock local-dev
status_for(@localhost, 'anything.example.test')
#=> 200

## localhost anchor - a nil detected host is not denied either
status_for(@localhost, nil)
#=> 200

## IP-literal anchor (the shipped spec/config.test.yaml posture) - inert
@iplit = build_mw(default_domain: nil, site_host: '127.0.0.1:3000')
[@iplit.allowed_hosts, @iplit.host_gate_active?]
#=> [[], false]

## IP-literal anchor - both surfaces stay reachable
both_surfaces(@iplit, 'anything.example.test')
#=> [200, 200]

## a routable anchor makes the DEFAULT (unset allowed_hosts) posture enforcing
build_mw(default_domain: 'example.com', site_host: '127.0.0.1:3000').host_gate_active?
#=> true

# =================================================================
# HOST GATE — the fail-closed BACKSTOP (explicit list, nothing enforceable)
# =================================================================
# The opposite of the inert rule, and deliberately so. An operator who writes
# ADMIN_ALLOWED_HOSTS=127.0.0.1 asked to RESTRICT the admin surfaces; going
# inert would serve them on every hostname instead — failing open on a typo.
# Onetime::Config.validate_admin_allowed_hosts! normally refuses this config at
# boot (see spec/unit/onetime/config/admin_allowed_hosts_spec.rb); the
# middleware still denies if it is ever constructed with one.

## IP-literal list - ACTIVE gate with an EMPTY allowlist
@ip_only = build_mw(hosts: ['127.0.0.1'])
[@ip_only.allowed_hosts, @ip_only.host_gate_active?]
#=> [[], true]

## IP-literal list - both surfaces are DENIED, not served
both_surfaces(@ip_only, 'anything.example.test')
#=> [404, 404]

## IP-literal list - the configured IP is denied too (it is never a detected host)
status_for(@ip_only, '127.0.0.1')
#=> 404

## localhost list - same backstop
@lh_only = build_mw(hosts: ['localhost', 'localhost.localdomain', '::1'])
[@lh_only.allowed_hosts, @lh_only.host_gate_active?, status_for(@lh_only, 'anything.example.test')]
#=> [[], true, 404]

## wildcard PATTERN is not a match-all and not the escape hatch: it DENIES
@pattern = build_mw(hosts: ['*.example.com'])
[@pattern.allowed_hosts, @pattern.host_gate_active?]
#=> [[], true]

## wildcard pattern - the host it appears to name is still denied
both_surfaces(@pattern, 'admin.example.com')
#=> [404, 404]

## non-ASCII entry (no IDN library ships here) - denies rather than widens
@idn = build_mw(hosts: ['bücher.example'])
[@idn.allowed_hosts, @idn.host_gate_active?, status_for(@idn, 'bücher.example')]
#=> [[], true, 404]

## the punycode form of that same host IS enforceable
@puny = build_mw(hosts: ['xn--bcher-kva.example'])
[@puny.allowed_hosts, status_for(@puny, 'xn--bcher-kva.example')]
#=> [['xn--bcher-kva.example'], 200]

## backstop denial is a 404, byte-identical to every other denial
@ip_only.call(admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9',
                        detected_host: 'anything.example.test')).first
#=> 404

## backstop does NOT touch non-admin paths
status_for(@ip_only, 'anything.example.test', path_info: '/dashboard')
#=> 200

## a wildcard pattern ALONGSIDE a routable host does not widen it
@pattern_mixed = build_mw(hosts: ['*.example.com', 'admin.example.com'])
[@pattern_mixed.allowed_hosts,
 status_for(@pattern_mixed, 'admin.example.com'),
 status_for(@pattern_mixed, 'other.example.com')]
#=> [['admin.example.com'], 200, 404]

## ONE routable entry among unenforceable ones activates the gate for that host
@one_routable = build_mw(hosts: ['127.0.0.1', 'admin.example.com'])
[@one_routable.host_gate_active?,
 status_for(@one_routable, 'admin.example.com'),
 status_for(@one_routable, 'other.example.com')]
#=> [true, 200, 404]

# =================================================================
# HOST PROVENANCE — the detected host, and nothing else
# =================================================================
# Two inputs must never decide admin reachability: HTTP_HOST (raw, bypasses the
# trust decision Rack::DetectHost already made about the peer) and
# env['onetime.domain_strategy'] (DomainStrategy honors an O-Domain-Context
# REQUEST HEADER override when development.domain_context_enabled is on).

## HTTP_HOST naming an allowed host does NOT admit a denied detected host
@provenance = build_mw(hosts: ['admin.example.com'])
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9',
                 detected_host: 'tenant.example.com', http_host: 'admin.example.com')
@provenance.call(@env).first
#=> 404

## HTTP_HOST naming a DENIED host does not evict an allowed detected host
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9',
                 detected_host: 'admin.example.com', http_host: 'tenant.example.com')
@provenance.call(@env).first
#=> 200

## a :canonical domain_strategy does not rescue a denied detected host
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9',
                 detected_host: 'tenant.example.com', domain_strategy: :canonical)
@provenance.call(@env).first
#=> 404

## a :custom domain_strategy does not deny an allowed detected host
@env = admin_env(script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9',
                 detected_host: 'admin.example.com', domain_strategy: :custom)
@provenance.call(@env).first
#=> 200

## HTTP_HOST alone (no detected host at all) fails closed
@env = admin_env(script_name: '', path_info: '/colonel', client_ip: '203.0.113.9',
                 http_host: 'admin.example.com')
@provenance.call(@env).first
#=> 404

# =================================================================
# HOST GATE — the env key is an accessor, not a literal
# =================================================================
# Rack::DetectHost.result_field_name is driven by the DETECTED_HOST env var. A
# hardcoded 'rack.detected_host' would read nil on a deployment that renames
# it — a blanket 404 on both surfaces.

## the middleware follows a renamed result field
@renamed_status = begin
  Rack::DetectHost.result_field_name = 'custom.detected_host'
  mw  = build_mw(hosts: ['admin.example.com'])
  env = Rack::MockRequest.env_for('http://example.com/colonel')
  env['SCRIPT_NAME'] = ''
  env['PATH_INFO'] = '/colonel'
  env['otto.client_ip'] = '203.0.113.9'
  env['custom.detected_host'] = 'admin.example.com'
  mw.call(env).first
ensure
  Rack::DetectHost.result_field_name = @orig_detected_field
end
#=> 200

## the field name was restored
Rack::DetectHost.result_field_name == @orig_detected_field
#=> true

# =================================================================
# BOTH GATES — independent, and either failure denies
# =================================================================

## both gates active - the middleware says so
@both = build_mw(hosts: ['admin.example.com'], cidrs: ['10.0.0.0/8'])
[@both.host_gate_active?, @both.network_gate_active?]
#=> [true, true]

## host pass + CIDR pass -> through to the auth layers (200)
status_for(@both, 'admin.example.com', client_ip: '10.0.0.5')
#=> 200

## host pass + CIDR fail -> 404
status_for(@both, 'admin.example.com', client_ip: '203.0.113.9')
#=> 404

## host fail + CIDR pass -> 404
status_for(@both, 'tenant.example.com', client_ip: '10.0.0.5')
#=> 404

## host fail + CIDR fail -> 404
status_for(@both, 'tenant.example.com', client_ip: '203.0.113.9')
#=> 404

## both gates active - the API surface behaves identically
[status_for(@both, 'admin.example.com', script_name: '/api/colonel', path_info: '/info', client_ip: '10.0.0.5'),
 status_for(@both, 'admin.example.com', script_name: '/api/colonel', path_info: '/info', client_ip: '203.0.113.9'),
 status_for(@both, 'tenant.example.com', script_name: '/api/colonel', path_info: '/info', client_ip: '10.0.0.5')]
#=> [200, 404, 404]

## both gates active - a non-admin path is untouched even when both would fail
status_for(@both, 'tenant.example.com', path_info: '/dashboard', client_ip: '203.0.113.9')
#=> 200

## both gates inactive - strict no-op on /colonel
@none = build_mw(hosts: [], cidrs: [], site_host: '127.0.0.1:3000')
[@none.host_gate_active?, @none.network_gate_active?, status_for(@none, 'anything.example.test')]
#=> [false, false, 200]

## both gates inactive - strict no-op on /api/colonel with no detected host
status_for(@none, nil, script_name: '/api/colonel', path_info: '/info')
#=> 200

## both gates inactive - non-admin paths obviously unaffected
status_for(@none, nil, path_info: '/dashboard')
#=> 200

# =================================================================
# The two denials are indistinguishable to the client
# =================================================================
# Operators tell a host denial from a network denial by the log message, never
# by the response. Same status, same headers, same bytes.

## /colonel - host denial and CIDR denial are byte-identical
@host_only = build_mw(hosts: ['admin.example.com'], cidrs: [])
@cidr_only = build_mw(hosts: [], cidrs: ['10.0.0.0/8'], site_host: '127.0.0.1:3000')
denial_triple(@host_only, 'tenant.example.com', '10.0.0.5', '', '/colonel') ==
  denial_triple(@cidr_only, 'tenant.example.com', '203.0.113.9', '', '/colonel')
#=> true

## /api/colonel - host denial and CIDR denial are byte-identical
denial_triple(@host_only, 'tenant.example.com', '10.0.0.5', '/api/colonel', '/info') ==
  denial_triple(@cidr_only, 'tenant.example.com', '203.0.113.9', '/api/colonel', '/info')
#=> true

## sanity - the two setups really did deny for DIFFERENT reasons
[@host_only.host_gate_active?, @host_only.network_gate_active?,
 @cidr_only.host_gate_active?, @cidr_only.network_gate_active?]
#=> [true, false, false, true]

## the backstop denial is byte-identical to a host-allowlist denial too
denial_triple(@ip_only, 'anything.example.test', '203.0.113.9', '', '/colonel') ==
  denial_triple(@host_only, 'tenant.example.com', '203.0.113.9', '', '/colonel')
#=> true

# Restore every global this file mutated: both admin lists, site.host, the
# features.domains block, and the DetectHost result field. `rake try:unit` runs
# all unit tryouts in one process — a leak here changes what later files see.
OT.conf['site']['admin'] = @orig_admin if @orig_admin
OT.conf['site']['host'] = @orig_site_host
OT.conf['features']['domains'] = @orig_domains if @orig_domains
Rack::DetectHost.result_field_name = @orig_detected_field
