# try/integration/middleware/detect_host_try.rb
#
# frozen_string_literal: true

# These tryouts test the DetectHost middleware functionality.
# The DetectHost middleware is responsible for determining the correct hostname
# from various HTTP headers, while filtering out invalid hosts like localhost
# and IP addresses.
#
# We're testing:
# 1. Header precedence (X-Forwarded-Host, X-Original-Host, Forwarded, Host)
# 2. Host validation (reject localhost, IPs)
# 3. Port stripping
# 4. Multiple host handling
# 5. Empty and missing header handling
# 6. Trusted proxy validation (forwarded headers only trusted from private IPs)

require_relative '../../support/test_helpers'

require 'logger'
require 'stringio'

require 'middleware/detect_host'

# Capture log output for verification
@log_output = StringIO.new
@logger = Logger.new(@log_output)
@app = ->(env) { [200, {}, ['OK']] }
@original_value = OT.debug?
OT.debug = true  # log messages are only avalable in debug mode
@middleware = Rack::DetectHost.new(@app, logger: @logger)

## X-Forwarded-Host takes precedence over Host header (from trusted proxy)
# REMOTE_ADDR must be a private IP for forwarded headers to be trusted
env = {'REMOTE_ADDR' => '10.0.0.1', 'HTTP_X_FORWARDED_HOST' => 'first.com', 'HTTP_HOST' => 'last.com'}
@middleware.call(env)
env['rack.detected_host']
#=> 'first.com'

## Strips port number from hostname
env = {'HTTP_HOST' => 'example.com:8080'}
@middleware.call(env)
env['rack.detected_host']
#=> 'example.com'

## Handles host with extra spaces and port
env = {'HTTP_HOST' => '  example.com:8080  '}
@middleware.call(env)
env['rack.detected_host']
#=> 'example.com'

## Rejects localhost as invalid host
env = {'HTTP_HOST' => 'localhost'}
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Rejects localhost with port as invalid host
env = {'HTTP_HOST' => 'localhost:3000'}
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Rejects IPv4 address as invalid host
env = {'HTTP_HOST' => '127.0.0.1'}
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Rejects IPv6 address as invalid host
env = {'HTTP_HOST' => '::1'}
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Takes first host when multiple are provided (from trusted proxy)
env = {'REMOTE_ADDR' => '192.168.1.1', 'HTTP_X_FORWARDED_HOST' => 'first.com, second.com'}
@middleware.call(env)
env['rack.detected_host']
#=> 'first.com'

## Handles missing headers gracefully
env = {}
@middleware.call(env)
output = @log_output.string
puts output
[env['rack.detected_host'], output.include?('Invalid host detected')]
#=> [nil, true]

## Always forwards request to app regardless of host validity
env = {'HTTP_HOST' => 'example.com'}
status, _, body = @middleware.call(env)
[status, body]
#=> [200, ['OK']]

## Ignores X-Forwarded-Host from direct public request (security)
# Direct requests from public IPs should not trust forwarded headers
env = {'REMOTE_ADDR' => '203.0.113.50', 'HTTP_X_FORWARDED_HOST' => 'spoofed.com', 'HTTP_HOST' => 'real.com'}
@middleware.call(env)
env['rack.detected_host']
#=> 'real.com'

## Trusts X-Forwarded-Host from private network (loopback)
env = {'REMOTE_ADDR' => '127.0.0.1', 'HTTP_X_FORWARDED_HOST' => 'forwarded.com', 'HTTP_HOST' => 'fallback.com'}
@middleware.call(env)
env['rack.detected_host']
#=> 'forwarded.com'

## Trusts X-Forwarded-Host from private network (RFC 1918)
env = {'REMOTE_ADDR' => '172.16.5.100', 'HTTP_X_FORWARDED_HOST' => 'internal.example.com', 'HTTP_HOST' => 'external.com'}
@middleware.call(env)
env['rack.detected_host']
#=> 'internal.example.com'



# Put everything back the way we found it
OT.debug = @original_value
