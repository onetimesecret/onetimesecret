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
# Client IP is resolved from the trusted-proxy-aware env['otto.client_ip'], so a
# raw X-Forwarded-For header cannot bypass the allowlist.
#
# Test categories:
#   1. Path matching (colonel_shell? / colonel_api?), full-path reconstruction
#   2. No-op when allowlist empty
#   3. Outside allowlist -> 404 on both surfaces
#   4. Inside allowlist -> pass-through to auth layers
#   5. Spoofed X-Forwarded-For cannot bypass

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

# Set the allowlist in config, then build a middleware instance that reads it.
def set_allowlist(cidrs)
  OT.conf['site'] ||= {}
  OT.conf['site']['admin'] ||= {}
  OT.conf['site']['admin']['allowed_cidrs'] = cidrs
  TestAdminNetworkIsolation.new(@mock_app)
end

# Build a Rack env for a full path, injecting the resolved (otto) client IP.
# script_name simulates Rack::URLMap mounting (colonel API is mounted at
# /api/colonel, so PATH_INFO is stripped to e.g. /info).
def admin_env(script_name:, path_info:, client_ip:, xff: nil)
  env = Rack::MockRequest.env_for("http://example.com#{script_name}#{path_info}")
  env['SCRIPT_NAME'] = script_name
  env['PATH_INFO'] = path_info
  env['otto.client_ip'] = client_ip if client_ip
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

# =================================================================
# No-op when allowlist is empty/unset (self-hosted default)
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

# Restore config to a clean empty allowlist so later tryouts see a no-op posture.
OT.conf['site']['admin']['allowed_cidrs'] = []
