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

require_relative '../test_helpers'

require 'stringio'
require 'middleware/detect_host'

# Capture log output for verification
@log_output = StringIO.new
@app = ->(env) { [200, {}, ['OK']] }
@middleware = Rack::DetectHost.new(@app, io: @log_output)

## X-Forwarded-Host takes precedence over Host header
env = {'HTTP_X_FORWARDED_HOST' => 'first.com', 'HTTP_HOST' => 'last.com'}
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

## Takes first host when multiple are provided
env = {'HTTP_X_FORWARDED_HOST' => 'first.com, second.com'}
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
