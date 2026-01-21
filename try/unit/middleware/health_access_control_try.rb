# try/unit/middleware/health_access_control_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Middleware::HealthAccessControl
#
# This middleware restricts health check endpoints (/health, /health/*, /auth/health)
# to requests from localhost and private network IPs.
# Public IPs receive a 403 JSON error response.
#
# IP classification is delegated to Otto::Privacy::IPPrivacy.private_or_localhost?
#
# Test categories:
#   1. health_endpoint? - Path matching for health endpoints
#   2. Otto::Privacy::IPPrivacy.private_or_localhost? - IP classification
#   3. call - Request flow (allow/deny based on IP and path)

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'rack/mock'
require 'json'
require_relative '../../../lib/onetime/middleware/health_access_control'

# Test subclass to expose private methods
class TestHealthAccessControl < Onetime::Middleware::HealthAccessControl
  public :health_endpoint?
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
# Otto::Privacy::IPPrivacy.private_or_localhost? - IPv4 loopback
# =================================================================

## Otto IP check - IPv4 localhost 127.0.0.1
Otto::Privacy::IPPrivacy.private_or_localhost?('127.0.0.1')
#=> true

## Otto IP check - IPv4 localhost 127.0.0.2
Otto::Privacy::IPPrivacy.private_or_localhost?('127.0.0.2')
#=> true

## Otto IP check - IPv6 localhost ::1
Otto::Privacy::IPPrivacy.private_or_localhost?('::1')
#=> true

# =================================================================
# Otto::Privacy::IPPrivacy.private_or_localhost? - RFC 1918 private ranges
# =================================================================

## Otto IP check - 10.0.0.1 is private
Otto::Privacy::IPPrivacy.private_or_localhost?('10.0.0.1')
#=> true

## Otto IP check - 10.255.255.255 is private
Otto::Privacy::IPPrivacy.private_or_localhost?('10.255.255.255')
#=> true

## Otto IP check - 172.16.0.1 is private
Otto::Privacy::IPPrivacy.private_or_localhost?('172.16.0.1')
#=> true

## Otto IP check - 172.31.255.255 is private
Otto::Privacy::IPPrivacy.private_or_localhost?('172.31.255.255')
#=> true

## Otto IP check - 192.168.0.1 is private
Otto::Privacy::IPPrivacy.private_or_localhost?('192.168.0.1')
#=> true

## Otto IP check - 192.168.255.255 is private
Otto::Privacy::IPPrivacy.private_or_localhost?('192.168.255.255')
#=> true

# =================================================================
# Otto::Privacy::IPPrivacy.private_or_localhost? - Public IPs (false)
# =================================================================

## Otto IP check - Google DNS 8.8.8.8 is public
Otto::Privacy::IPPrivacy.private_or_localhost?('8.8.8.8')
#=> false

## Otto IP check - Cloudflare DNS 1.1.1.1 is public
Otto::Privacy::IPPrivacy.private_or_localhost?('1.1.1.1')
#=> false

## Otto IP check - Random public IP 203.0.113.50
Otto::Privacy::IPPrivacy.private_or_localhost?('203.0.113.50')
#=> false

## Otto IP check - IPv6 public 2001:db8::1
Otto::Privacy::IPPrivacy.private_or_localhost?('2001:db8::1')
#=> false

# =================================================================
# Otto::Privacy::IPPrivacy.private_or_localhost? - Edge cases
# =================================================================

## Otto IP check - Nil IP returns false (fail closed)
Otto::Privacy::IPPrivacy.private_or_localhost?(nil)
#=> false

## Otto IP check - Empty string returns false (fail closed)
Otto::Privacy::IPPrivacy.private_or_localhost?('')
#=> false

## Otto IP check - Invalid IP string returns false
Otto::Privacy::IPPrivacy.private_or_localhost?('not_an_ip')
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
