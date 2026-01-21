# try/unit/middleware/health_access_control_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Middleware::HealthAccessControl
#
# This middleware restricts health check endpoints (/health, /health/*, /auth/health)
# to requests from localhost and private network IPs (RFC 1918, link-local, loopback).
# Public IPs receive a 403 JSON error response.
#
# Test categories:
#   1. health_endpoint? - Path matching for health endpoints
#   2. private_network? - IP classification (private vs public)
#   3. call - Request flow (allow/deny based on IP and path)

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'rack/mock'
require 'json'
require_relative '../../../lib/onetime/middleware/health_access_control'

# Test subclass to expose private methods
class TestHealthAccessControl < Onetime::Middleware::HealthAccessControl
  public :health_endpoint?
  public :private_network?
end

# Mock app that returns 200 OK
@mock_app = ->(env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }
@middleware = TestHealthAccessControl.new(@mock_app)

# Helper to create mock request with specific IP and path
def create_env(path, ip)
  env = Rack::MockRequest.env_for("http://example.com#{path}")
  env['REMOTE_ADDR'] = ip
  env
end

# =================================================================
# health_endpoint? - Path matching
# =================================================================

## health_endpoint? - Matches exact /health path
@middleware.health_endpoint?('/health')
#=> true

## health_endpoint? - Matches /health/advanced subpath
@middleware.health_endpoint?('/health/advanced')
#=> true

## health_endpoint? - Matches /health/any/nested/path
@middleware.health_endpoint?('/health/foo/bar/baz')
#=> true

## health_endpoint? - Matches /auth/health path
@middleware.health_endpoint?('/auth/health')
#=> true

## health_endpoint? - Does NOT match root path
@middleware.health_endpoint?('/')
#=> false

## health_endpoint? - Does NOT match /api path
@middleware.health_endpoint?('/api')
#=> false

## health_endpoint? - Does NOT match /healthcheck (different path)
@middleware.health_endpoint?('/healthcheck')
#=> false

## health_endpoint? - Does NOT match /health-status (different path)
@middleware.health_endpoint?('/health-status')
#=> false

## health_endpoint? - Does NOT match path containing health elsewhere
@middleware.health_endpoint?('/api/health-check')
#=> false

## health_endpoint? - Does NOT match /healthy (prefix only)
@middleware.health_endpoint?('/healthy')
#=> false

# =================================================================
# private_network? - IPv4 loopback addresses
# =================================================================

## private_network? - IPv4 localhost 127.0.0.1
@middleware.private_network?('127.0.0.1')
#=> true

## private_network? - IPv4 localhost 127.0.0.2
@middleware.private_network?('127.0.0.2')
#=> true

## private_network? - IPv4 localhost 127.255.255.255
@middleware.private_network?('127.255.255.255')
#=> true

# =================================================================
# private_network? - IPv6 loopback
# =================================================================

## private_network? - IPv6 localhost ::1
@middleware.private_network?('::1')
#=> true

# =================================================================
# private_network? - RFC 1918 private ranges (10.0.0.0/8)
# =================================================================

## private_network? - 10.0.0.1 is private
@middleware.private_network?('10.0.0.1')
#=> true

## private_network? - 10.255.255.255 is private
@middleware.private_network?('10.255.255.255')
#=> true

## private_network? - 10.100.50.25 is private
@middleware.private_network?('10.100.50.25')
#=> true

# =================================================================
# private_network? - RFC 1918 private ranges (172.16.0.0/12)
# =================================================================

## private_network? - 172.16.0.1 is private
@middleware.private_network?('172.16.0.1')
#=> true

## private_network? - 172.31.255.255 is private
@middleware.private_network?('172.31.255.255')
#=> true

## private_network? - 172.20.10.5 is private
@middleware.private_network?('172.20.10.5')
#=> true

## private_network? - 172.15.0.1 is NOT private (outside range)
@middleware.private_network?('172.15.0.1')
#=> false

## private_network? - 172.32.0.1 is NOT private (outside range)
@middleware.private_network?('172.32.0.1')
#=> false

# =================================================================
# private_network? - RFC 1918 private ranges (192.168.0.0/16)
# =================================================================

## private_network? - 192.168.0.1 is private
@middleware.private_network?('192.168.0.1')
#=> true

## private_network? - 192.168.255.255 is private
@middleware.private_network?('192.168.255.255')
#=> true

## private_network? - 192.168.1.100 is private
@middleware.private_network?('192.168.1.100')
#=> true

## private_network? - 192.167.0.1 is NOT private (outside range)
@middleware.private_network?('192.167.0.1')
#=> false

# =================================================================
# private_network? - Link-local addresses
# =================================================================

## private_network? - IPv4 link-local 169.254.0.1
@middleware.private_network?('169.254.0.1')
#=> true

## private_network? - IPv4 link-local 169.254.255.255
@middleware.private_network?('169.254.255.255')
#=> true

## private_network? - IPv6 link-local fe80::1
@middleware.private_network?('fe80::1')
#=> true

## private_network? - IPv6 link-local fe80::abc:def:123:456
@middleware.private_network?('fe80::abc:def:123:456')
#=> true

# =================================================================
# private_network? - IPv6 unique local (fc00::/7)
# =================================================================

## private_network? - IPv6 unique local fc00::1
@middleware.private_network?('fc00::1')
#=> true

## private_network? - IPv6 unique local fd00::1
@middleware.private_network?('fd00::1')
#=> true

# =================================================================
# private_network? - Public IPs (should return false)
# =================================================================

## private_network? - Google DNS 8.8.8.8 is public
@middleware.private_network?('8.8.8.8')
#=> false

## private_network? - Cloudflare DNS 1.1.1.1 is public
@middleware.private_network?('1.1.1.1')
#=> false

## private_network? - Random public IP 203.0.113.50
@middleware.private_network?('203.0.113.50')
#=> false

## private_network? - Random public IP 45.67.89.123
@middleware.private_network?('45.67.89.123')
#=> false

## private_network? - IPv6 public 2001:db8::1
@middleware.private_network?('2001:db8::1')
#=> false

## private_network? - IPv6 public 2607:f8b0:4004:800::200e (Google)
@middleware.private_network?('2607:f8b0:4004:800::200e')
#=> false

# =================================================================
# private_network? - Edge cases
# =================================================================

## private_network? - Nil IP returns true (safe default)
@middleware.private_network?(nil)
#=> true

## private_network? - Empty string returns true (safe default)
@middleware.private_network?('')
#=> true

## private_network? - Invalid IP string returns false (deny access)
@middleware.private_network?('not_an_ip')
#=> false

## private_network? - Malformed IP returns false
@middleware.private_network?('256.256.256.256')
#=> false

## private_network? - Partial IP returns false
@middleware.private_network?('192.168')
#=> false

## private_network? - IP with port returns false (invalid format)
@middleware.private_network?('192.168.1.1:8080')
#=> false

# =================================================================
# call - Allow health requests from private IPs
# =================================================================

## call - Allows /health from localhost 127.0.0.1
@env = create_env('/health', '127.0.0.1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Allows /health from ::1 (IPv6 localhost)
@env = create_env('/health', '::1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Allows /health/advanced from private IP 10.0.0.5
@env = create_env('/health/advanced', '10.0.0.5')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Allows /auth/health from 192.168.1.1
@env = create_env('/auth/health', '192.168.1.1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Allows /health from 172.16.0.1
@env = create_env('/health', '172.16.0.1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

# =================================================================
# call - Block health requests from public IPs with 403
# =================================================================

## call - Blocks /health from public IP 8.8.8.8
@env = create_env('/health', '8.8.8.8')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 403

## call - Returns JSON error body for blocked request
@env = create_env('/health', '8.8.8.8')
@status, @headers, @body = @middleware.call(@env)
@response_body = JSON.parse(@body.first)
@response_body['error']
#=> 'Health endpoints restricted to private networks'

## call - Returns JSON content type for blocked request
@env = create_env('/health', '8.8.8.8')
@status, @headers, @body = @middleware.call(@env)
@headers['Content-Type']
#=> 'application/json'

## call - Blocks /health/advanced from public IP 1.1.1.1
@env = create_env('/health/advanced', '1.1.1.1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 403

## call - Blocks /auth/health from public IP 203.0.113.50
@env = create_env('/auth/health', '203.0.113.50')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 403

## call - Blocks /health from IPv6 public address
@env = create_env('/health', '2001:db8::1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 403

# =================================================================
# call - Pass non-health requests through regardless of IP
# =================================================================

## call - Passes / through from public IP
@env = create_env('/', '8.8.8.8')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Passes /api/secrets through from public IP
@env = create_env('/api/secrets', '203.0.113.50')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Passes /healthcheck through from public IP (not a health endpoint)
@env = create_env('/healthcheck', '1.1.1.1')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Passes /dashboard through from public IP
@env = create_env('/dashboard', '45.67.89.123')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200

## call - Passes /api/health-check through from public IP
@env = create_env('/api/health-check', '8.8.8.8')
@status, @headers, @body = @middleware.call(@env)
@status
#=> 200
