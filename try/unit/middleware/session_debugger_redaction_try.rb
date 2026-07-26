# try/unit/middleware/session_debugger_redaction_try.rb
#
# frozen_string_literal: true

# Tests for Rack::SessionDebugger header redaction (2026-06-22
# assessment OBS1): the logged response-headers hash must have
# Set-Cookie / Cookie / Authorization values replaced with
# '[REDACTED]', while the actual response headers passed through
# the middleware remain untouched.

require_relative '../../support/test_helpers'

OT.boot! :test, false

require_relative '../../../lib/middleware/session_debugger'

@mock_app   = ->(_env) { [200, { 'content-type' => 'text/plain' }, ['OK']] }
@middleware = Rack::SessionDebugger.new(@mock_app)

@headers = {
  'content-type' => 'application/json',
  'set-cookie' => 'rack.session=SECRETVALUE; HttpOnly',
  'authorization' => 'Basic dXNlcjpwYXNz',
}

# =================================================================
# redact_headers
# =================================================================

## Set-Cookie value is redacted in the logged copy
@redacted = @middleware.send(:redact_headers, @headers)
@redacted['set-cookie']
#=> "[REDACTED]"

## Authorization value is redacted
@redacted['authorization']
#=> "[REDACTED]"

## Non-sensitive headers pass through unchanged
@redacted['content-type']
#=> "application/json"

## Original headers hash is not mutated
@headers['set-cookie']
#=> "rack.session=SECRETVALUE; HttpOnly"

## Matching is case-insensitive (legacy/request-side header shapes)
@middleware.send(:redact_headers, 'Set-Cookie' => 'sid=abc', 'Cookie' => 'sid=abc')
#=> {"Set-Cookie"=>"[REDACTED]", "Cookie"=>"[REDACTED]"}

## Handles Rack::Headers-style objects via to_h
require 'rack/headers'
rack_headers = Rack::Headers.new
rack_headers['Set-Cookie'] = 'sid=abc'
@middleware.send(:redact_headers, rack_headers)['set-cookie']
#=> "[REDACTED]"
