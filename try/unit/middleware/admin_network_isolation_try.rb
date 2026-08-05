# try/unit/middleware/admin_network_isolation_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Middleware::AdminNetworkIsolation
#
# This middleware optionally restricts the Colonel admin surfaces
# (/colonel shell + /api/colonel API) to a configured CIDR allowlist
# (site.admin.allowed_cidrs). A request from OUTSIDE the allowlist receives a
# 404 (indistinguishable-from-absent, NOT 403). When the allowlist is
# unset/empty the middleware is a strict no-op (both surfaces reachable).
#
# Client IP is resolved via Otto::Utils.resolve_client_ip fed the SAME
# Otto::Security::Config as IPPrivacyMiddleware -- never a raw header, and
# never the IP-privacy-masked value (#3912): this middleware is mounted
# BEFORE IPPrivacyMiddleware precisely so it sees the real client IP before
# masking would otherwise have already overwritten REMOTE_ADDR /
# X-Forwarded-For. A /32 (or /128) allowlist entry -- finer than the masking
# granularity (/24 IPv4, /48 IPv6) -- would otherwise silently never match
# the masked value, or silently over-match the whole masked block.
#
# Test categories:
#   1. Path matching (colonel_shell? / colonel_api?), full-path reconstruction
#   2. No-op when allowlist empty
#   3. Outside allowlist -> 404 on both surfaces
#   4. Inside allowlist -> pass-through to auth layers
#   5. Spoofed X-Forwarded-For (from an untrusted peer) cannot bypass
#   6. Masking interaction: a /32 entry matches the real IP even though the
#      masked value (what env['otto.client_ip'] would hold, downstream of
#      this middleware) never would (#3912 core repro)
#   7. IPv4-mapped IPv6 client normalizes to match an IPv4 CIDR entry

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'rack/mock'
require 'json'
require_relative '../../../lib/onetime/middleware/admin_network_isolation'

# Test subclass to expose private predicates
class TestAdminNetworkIsolation < Onetime::Middleware::AdminNetworkIsolation
  public :admin_surface?, :colonel_shell?, :colonel_api?, :request_path, :allowed?
end

# Mock app that returns 200 OK — stands in for the downstream auth layers.
@mock_app = ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }

# No trusted proxy declared: Otto::Utils.resolve_client_ip resolves straight
# from REMOTE_ADDR (the direct-connect default — matches the self-hosted
# posture most of these examples exercise).
@direct_config = Otto::Security::Config.new

# A trusted reverse proxy IS declared, for the spoofed-XFF examples: only
# then does resolve_client_ip walk X-Forwarded-For at all.
@proxied_config = Otto::Security::Config.new
@proxied_config.add_trusted_proxy('192.0.2.0/24') # the (fictional) proxy tier

# Set the allowlist in config, then build a middleware instance that reads it.
def set_allowlist(cidrs, security_config: @direct_config)
  OT.conf['site'] ||= {}
  OT.conf['site']['admin'] ||= {}
  OT.conf['site']['admin']['allowed_cidrs'] = cidrs
  TestAdminNetworkIsolation.new(@mock_app, security_config)
end

# Build a Rack env for a full path. remote_addr is the direct TCP peer
# (REMOTE_ADDR); xff simulates a proxy-forwarded chain. script_name simulates
# Rack::URLMap mounting (colonel API is mounted at /api/colonel, so
# PATH_INFO is stripped to e.g. /info).
def admin_env(script_name:, path_info:, remote_addr:, xff: nil)
  env = Rack::MockRequest.env_for("http://example.com#{script_name}#{path_info}")
  env['SCRIPT_NAME'] = script_name
  env['PATH_INFO'] = path_info
  env['REMOTE_ADDR'] = remote_addr if remote_addr
  env.delete('REMOTE_ADDR') if remote_addr.nil?
  env['HTTP_X_FORWARDED_FOR'] = xff if xff
  env
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

## allowed? - IPv4-mapped IPv6 client normalizes to match an IPv4 CIDR entry (#3912)
## (::ffff:10.1.2.3 is the dual-stack-socket form of 10.1.2.3)
@mw.allowed?('::ffff:10.1.2.3')
#=> true

# =================================================================
# No-op when allowlist is empty/unset (self-hosted default)
# =================================================================

## empty allowlist - /colonel from a public IP passes through (200)
@noop = set_allowlist([])
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '203.0.113.9')
@status, _, _ = @noop.call(@env)
@status
#=> 200

## empty allowlist - /api/colonel from a public IP passes through (200)
@env = admin_env(script_name: '/api/colonel', path_info: '/info', remote_addr: '203.0.113.9')
@status, _, _ = @noop.call(@env)
@status
#=> 200

## nil allowlist - also a no-op
@nilmw = set_allowlist(nil)
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '203.0.113.9')
@status, _, _ = @nilmw.call(@env)
@status
#=> 200

# =================================================================
# Configured: outside the allowlist -> 404 on BOTH surfaces
# =================================================================

## outside allowlist - /colonel shell returns 404 (not 403)
@iso = set_allowlist(['10.0.0.0/8', '100.64.0.0/10'])
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
@status
#=> 404

## outside allowlist - /colonel shell returns HTML content type
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
@headers['Content-Type']
#=> 'text/html; charset=utf-8'

## outside allowlist - /colonel/customers subpath returns 404
@env = admin_env(script_name: '', path_info: '/colonel/customers', remote_addr: '8.8.8.8')
@status, _, _ = @iso.call(@env)
@status
#=> 404

## outside allowlist - /api/colonel returns 404
@env = admin_env(script_name: '/api/colonel', path_info: '/info', remote_addr: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
@status
#=> 404

## outside allowlist - /api/colonel returns JSON content type + error body
@env = admin_env(script_name: '/api/colonel', path_info: '/info', remote_addr: '203.0.113.9')
@status, @headers, @body = @iso.call(@env)
[@headers['Content-Type'], JSON.parse(@body.first)['error']]
#=> ['application/json', 'Not Found']

## outside allowlist - unresolvable client IP fails closed (404)
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: nil)
@env.delete('HTTP_X_FORWARDED_FOR')
@status, _, _ = @iso.call(@env)
@status
#=> 404

# =================================================================
# Configured: inside the allowlist -> pass through to auth layers
# =================================================================

## inside allowlist - /colonel from 10.0.0.5 passes through (200)
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '10.0.0.5')
@status, _, _ = @iso.call(@env)
@status
#=> 200

## inside allowlist - /api/colonel from Tailscale CGNAT passes through (200)
@env = admin_env(script_name: '/api/colonel', path_info: '/info', remote_addr: '100.64.7.7')
@status, _, _ = @iso.call(@env)
@status
#=> 200

## configured - non-admin path passes through regardless of IP
@env = admin_env(script_name: '', path_info: '/dashboard', remote_addr: '203.0.113.9')
@status, _, _ = @iso.call(@env)
@status
#=> 200

# =================================================================
# Spoofed X-Forwarded-For cannot bypass the allowlist
# =================================================================
# resolve_client_ip only honors X-Forwarded-For from a TRUSTED proxy peer
# (REMOTE_ADDR). An untrusted direct peer's forged XFF is ignored entirely —
# REMOTE_ADDR itself is authoritative.

## spoofed XFF from an untrusted direct peer - REMOTE_ADDR is authoritative, still denied (404)
@iso_direct = set_allowlist(['10.0.0.0/8', '100.64.0.0/10']) # @direct_config: no trusted proxy
@env = admin_env(
  script_name: '/api/colonel',
  path_info: '/info',
  remote_addr: '203.0.113.9', # untrusted direct peer, outside the allowlist
  xff: '10.0.0.5',            # attacker-supplied header claiming an allowed IP
)
@status, _, _ = @iso_direct.call(@env)
@status
#=> 404

# =================================================================
# Trusted-proxy chain - resolves the real client past a trusted hop
# =================================================================

## behind the trusted proxy - the forwarded (real) client IP is used, and allowed
@iso_proxied = set_allowlist(['203.0.113.0/24'], security_config: @proxied_config)
@env = admin_env(
  script_name: '',
  path_info: '/colonel',
  remote_addr: '192.0.2.10', # the trusted proxy hop
  xff: '203.0.113.7',        # real client, inside the allowlist
)
@status, _, _ = @iso_proxied.call(@env)
@status
#=> 200

## behind the trusted proxy - the forwarded (real) client IP is used, and denied
@iso_proxied = set_allowlist(['203.0.113.0/24'], security_config: @proxied_config)
@env = admin_env(
  script_name: '',
  path_info: '/colonel',
  remote_addr: '192.0.2.10', # the trusted proxy hop
  xff: '8.8.8.8',            # real client, outside the allowlist
)
@status, _, _ = @iso_proxied.call(@env)
@status
#=> 404

# =================================================================
# Masking interaction (#3912 core repro)
# =================================================================
#
# The bug: AdminNetworkIsolation used to read env['otto.client_ip'], which
# IPPrivacyMiddleware (mounted earlier, before the fix) had already masked to
# a /24 (IPv4) or /48 (IPv6) boundary. A /32 allowlist entry for the exact
# admin host then NEVER matched -- only the coarser masked block did. Fixed
# by mounting this middleware BEFORE IPPrivacyMiddleware and resolving the
# real IP itself, so it never observes the masked value at all. These
# examples pin that: build BOTH middlewares in the real stack order (this one
# first) and confirm the real IP is what the containment check sees, distinct
# from what IPPrivacyMiddleware would go on to mask it to downstream.

## a /32 entry for the exact real IP passes (this middleware never sees the masked value)
@masking_config = Otto::Security::Config.new
@masking_config.ip_privacy_config.mask_private_ips = true
OT.conf['site']['admin']['allowed_cidrs'] = ['203.0.113.7/32']
@exact_host_iso = TestAdminNetworkIsolation.new(@mock_app, @masking_config)
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '203.0.113.7')
@status, _, _ = @exact_host_iso.call(@env)
@status
#=> 200

## the same request denied for a neighbor on the same /24 (no over-match via a masked .0)
@env = admin_env(script_name: '', path_info: '/colonel', remote_addr: '203.0.113.9')
@status, _, _ = @exact_host_iso.call(@env)
@status
#=> 404

## confirms the repro premise: masking 203.0.113.7 to its /24 network boundary
## produces .0 -- the value the OLD (buggy) code compared the /32 entry
## against, via env['otto.client_ip'] once IPPrivacyMiddleware had masked it
IPAddr.new('203.0.113.7/24').to_range.first.to_s
#=> '203.0.113.0'

## ...and a /32 can never be persuaded it contains that masked /24 network
## address -- which is exactly why the OLD code kept denying the legitimate
## exact-host operator even though their real IP matched the entry
IPAddr.new('203.0.113.7/32').include?(IPAddr.new('203.0.113.0'))
#=> false

# Restore config to a clean empty allowlist so later tryouts see a no-op posture.
OT.conf['site']['admin']['allowed_cidrs'] = []
