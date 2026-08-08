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
# 6. Trusted proxy validation (tri-state, otto#228): when
#    env['otto.via_trusted_proxy'] is PRESENT it is authoritative in both
#    directions — true grants forwarded-header trust, false (or any
#    non-true value) denies it. When the key is ABSENT (no proxy trust
#    configured, or no IPPrivacyMiddleware mounted) the legacy heuristic
#    applies: a private/loopback REMOTE_ADDR grants trust.

require_relative '../../support/test_helpers'

require 'logger'
require 'stringio'

require 'middleware/detect_host'

# Capture log output for verification
@log_output     = StringIO.new
@logger         = Logger.new(@log_output)
@app            = ->(_env) { [200, {}, ['OK']] }
@original_value = OT.debug?
OT.debug        = true  # log messages are only avalable in debug mode
@middleware     = Rack::DetectHost.new(@app, logger: @logger)

## X-Forwarded-Host takes precedence over Host header (from trusted proxy)
# REMOTE_ADDR must be a private IP for forwarded headers to be trusted
env = { 'REMOTE_ADDR' => '10.0.0.1', 'HTTP_X_FORWARDED_HOST' => 'first.com', 'HTTP_HOST' => 'last.com' }
@middleware.call(env)
env['rack.detected_host']
#=> 'first.com'

## Strips port number from hostname
env = { 'HTTP_HOST' => 'example.com:8080' }
@middleware.call(env)
env['rack.detected_host']
#=> 'example.com'

## Handles host with extra spaces and port
env = { 'HTTP_HOST' => '  example.com:8080  ' }
@middleware.call(env)
env['rack.detected_host']
#=> 'example.com'

## Rejects localhost as invalid host
env = { 'HTTP_HOST' => 'localhost' }
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Rejects localhost with port as invalid host
env = { 'HTTP_HOST' => 'localhost:3000' }
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Rejects IPv4 address as invalid host
env = { 'HTTP_HOST' => '127.0.0.1' }
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Rejects IPv6 address as invalid host
env = { 'HTTP_HOST' => '::1' }
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Invalid host detected')]
#=> [nil, true]

## Takes first host when multiple are provided (from trusted proxy)
env = { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_X_FORWARDED_HOST' => 'first.com, second.com' }
@middleware.call(env)
env['rack.detected_host']
#=> 'first.com'

## Extracts host from the first RFC 7239 Forwarded element
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for=203.0.113.7;host=forwarded.example.com;proto=https',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'forwarded.example.com'

## Handles a quoted RFC 7239 host value and strips its port
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for=203.0.113.7;host="Forwarded.Example.COM:8443";proto=https',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'forwarded.example.com'

## Honors only the first Forwarded element, without splitting on quoted commas
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for="client,alias";host=first.example.com, for=203.0.113.8;host=second.example.com',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'first.example.com'

## Uses the earliest host parameter when the first element lacks one,
## mirroring Rack::Utils.forwarded_values and the X-Forwarded-Host
## first-value convention
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for=203.0.113.7;proto=https, for=203.0.113.8;host=second.example.com',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'second.example.com'

## Falls back when no Forwarded element carries a host parameter
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for=203.0.113.7;proto=https, for=203.0.113.8;proto=https',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## A non-RFC bare hostname in Forwarded is not a host parameter; falls back
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'legacy.example.com',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## A bracketed IPv6 Forwarded host is rejected (domain names required)
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for=203.0.113.7;host="[2001:db8::1]:8443"',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## X-Original-URL (IIS/ARR) contributes a host when it carries an absolute URL
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_X_ORIGINAL_URL' => 'https://original.example.com/admin?tab=1',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'original.example.com'

## X-Original-URL with the usual IIS path-only form falls through
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_X_ORIGINAL_URL' => '/admin?tab=1',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## X-Rewrite-URL (IIS URL Rewrite) contributes a host from an absolute URL
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_X_REWRITE_URL' => 'https://rewrite.example.com/page',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'rewrite.example.com'

## X-Original-Host takes precedence over X-Original-URL
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_X_ORIGINAL_HOST' => 'orig-host.example.com',
  'HTTP_X_ORIGINAL_URL' => 'https://orig-url.example.com/page',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'orig-host.example.com'

## IIS URL headers are ignored from untrusted sources like other forwarded headers
env = {
  'REMOTE_ADDR' => '203.0.113.99',
  'HTTP_X_ORIGINAL_URL' => 'https://spoofed.example.com/page',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## Header junk in X-Forwarded-Host (invalid hostname characters) is rejected
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_X_FORWARDED_HOST' => 'semi;colon.example.com',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## A bracketed IPv6 X-Forwarded-Host no longer yields a mangled host
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_X_FORWARDED_HOST' => '[2001:db8::1]:8080',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## A malformed quoted Forwarded value fails closed and falls back to Host
env = {
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_FORWARDED' => 'for=203.0.113.7;host="unterminated.example.com',
  'HTTP_HOST' => 'fallback.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'fallback.example.com'

## Handles missing headers gracefully
env    = {}
@middleware.call(env)
output = @log_output.string
puts output
[env['rack.detected_host'], output.include?('Invalid host detected')]
#=> [nil, true]

## Always forwards request to app regardless of host validity
env             = { 'HTTP_HOST' => 'example.com' }
status, _, body = @middleware.call(env)
[status, body]
#=> [200, ['OK']]

## Ignores X-Forwarded-Host from direct public request (security)
# Direct requests from public IPs should not trust forwarded headers
env = { 'REMOTE_ADDR' => '203.0.113.50', 'HTTP_X_FORWARDED_HOST' => 'spoofed.com', 'HTTP_HOST' => 'real.com' }
@middleware.call(env)
env['rack.detected_host']
#=> 'real.com'

## Trusts X-Forwarded-Host from private network (loopback)
env = { 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_X_FORWARDED_HOST' => 'forwarded.com', 'HTTP_HOST' => 'fallback.com' }
@middleware.call(env)
env['rack.detected_host']
#=> 'forwarded.com'

## Trusts X-Forwarded-Host from private network (RFC 1918)
env = { 'REMOTE_ADDR' => '172.16.5.100', 'HTTP_X_FORWARDED_HOST' => 'internal.example.com', 'HTTP_HOST' => 'external.com' }
@middleware.call(env)
env['rack.detected_host']
#=> 'internal.example.com'

## Trusts forwarded headers when otto.via_trusted_proxy is true, even with
## public REMOTE_ADDR. Regression: with TRUSTED_PROXY_ENABLED, Otto's
## IPPrivacyMiddleware rewrites REMOTE_ADDR to the resolved public visitor
## IP before DetectHost runs; the private_ip? heuristic then discarded
## forwarded host headers and every custom domain fell back to canonical.
env = {
  'REMOTE_ADDR' => '203.0.113.50',
  'otto.via_trusted_proxy' => true,
  'HTTP_APX_INCOMING_HOST' => 'custom.example.com',
  'HTTP_HOST' => 'canonical.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'custom.example.com'

## A false key is an AUTHORITATIVE DENY (tri-state, otto#228), even with a
## private REMOTE_ADDR: otto writes the key only when the operator
## configured proxy trust, so false means "trust is configured and this
## peer failed it". Honoring the private-IP heuristic anyway would let any
## request resolving to a private REMOTE_ADDR bypass the operator's
## explicit trust decision. (The pre-tri-state grant-only OR existed
## because otto wrote false on every unconfigured request, making false
## ambiguous — that ambiguity is gone: unconfigured deployments get an
## ABSENT key, pinned below.)
env = {
  'REMOTE_ADDR' => '10.0.0.1',
  'otto.via_trusted_proxy' => false,
  'HTTP_X_FORWARDED_HOST' => 'proxied.example.com',
  'HTTP_HOST' => 'direct.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'direct.example.com'

## Non-boolean key values (nil, or a truthy-looking string from a future
## otto) never grant trust — only `true` does. With a public REMOTE_ADDR
## the request degrades gracefully to the Host header instead of a
## spoofable trust cliff.
[nil, 'true'].map do |value|
  env = {
    'REMOTE_ADDR' => '203.0.113.50',
    'otto.via_trusted_proxy' => value,
    'HTTP_X_FORWARDED_HOST' => 'spoofed.example.com',
    'HTTP_HOST' => 'real.example.com',
  }
  @middleware.call(env)
  env['rack.detected_host']
end
#=> ['real.example.com', 'real.example.com']

## A PRESENT non-boolean key suppresses the private-IP heuristic too:
## presence implies the authoritative contract, so the value must be
## exactly true to grant. (nil here means "key present, value nil" —
## distinct from the absent-key fallback pinned below.)
env = {
  'REMOTE_ADDR' => '10.0.0.1',
  'otto.via_trusted_proxy' => nil,
  'HTTP_X_FORWARDED_HOST' => 'proxied.example.com',
  'HTTP_HOST' => 'direct.example.com',
}
@middleware.call(env)
env['rack.detected_host']
#=> 'direct.example.com'

## Discarding Apx-Incoming-Host from an untrusted source escalates the log
## to WARN — the 2026-08-05 incident signature (custom domains silently
## falling back to canonical under Approximated ingress).
env = {
  'REMOTE_ADDR' => '203.0.113.50',
  'HTTP_APX_INCOMING_HOST' => 'custom.example.com',
  'HTTP_HOST' => 'canonical.example.com',
}
@middleware.call(env)
[env['rack.detected_host'], @log_output.string.include?('Apx-Incoming-Host present')]
#=> ['canonical.example.com', true]

## Falls back to private_ip? heuristic when otto.via_trusted_proxy is absent
## (bare-Rack stacks without IPPrivacyMiddleware)
env = { 'REMOTE_ADDR' => '10.0.0.1', 'HTTP_X_FORWARDED_HOST' => 'forwarded.example.com', 'HTTP_HOST' => 'direct.example.com' }
@middleware.call(env)
env['rack.detected_host']
#=> 'forwarded.example.com'

# Put everything back the way we found it
OT.debug = @original_value
