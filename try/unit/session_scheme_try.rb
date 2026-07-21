# try/unit/session_scheme_try.rb
#
# frozen_string_literal: true

#
# Session Scheme / Secure-Cookie Test Suite (#3837, root cause of #3831)
#
# Covers the three-part fix for the silently-dropped Secure session cookie
# behind a TLS-terminating proxy that does NOT forward X-Forwarded-Proto
# (e.g. Cloudflare Tunnel):
#
#   Part 1: Onetime::Middleware::AssumeHttps upgrades the request scheme to
#           HTTPS when site.network.assume_https is enabled (upgrade-only).
#   Part 2: Onetime::Session#security_matches? emits a throttled warning when
#           a Secure cookie is dropped because the request is seen as non-SSL.
#
# The unit under test for cookie persistence is Rack's own decision method
# security_matches?: when it returns false, commit_session returns EARLY and
# NO Set-Cookie is written. Asserting its boolean is the precise, deterministic
# proxy for "session persisted / not persisted".

# Force simple mode before boot (matches try/unit/session_try.rb).
ENV['AUTHENTICATION_MODE'] = 'simple'

require 'rack'

require_relative '../support/test_helpers'

require 'onetime'
require 'onetime/session'
require 'onetime/middleware/assume_https'

OT.boot! :test, false

Session = Onetime::Session

# Minimal downstream app for driving the middleware.
class MockApp
  def call(_env)
    [200, {}, ['OK']]
  end
end

# Capture OT.lw so we can assert the Part 2 dropped-cookie warning fires.
# OT.lw is a class method on Onetime; override it to append to a constant
# array (closure-captured). Single-file tryout process, so no cross-file leak.
CAPTURED_WARNINGS = []
CAPTURED_PAYLOADS = []
OT.define_singleton_method(:lw) do |*msgs, **payload|
  CAPTURED_WARNINGS << msgs.join(' ')
  CAPTURED_PAYLOADS << payload
end

@app     = MockApp.new
@secret  = SecureRandom.hex(64)
@session = Session.new(@app, { secret: @secret, key: 'test.session', expire_after: 3600 })

# Build a Rack::Request from a raw env hash.
def request_for(env = {})
  Rack::Request.new(env)
end

# Reset the process-wide throttle guard so each warn-expecting case can fire.
def reset_warn_guard!
  Onetime::Session.secure_cookie_warned_at = nil
  CAPTURED_WARNINGS.clear
  CAPTURED_PAYLOADS.clear
end

# Set the AssumeHttps flag in the live config, then build a fresh middleware
# (the flag is cached at #initialize). String keys: OT.conf is string-keyed.
def assume_https_middleware(enabled)
  (OT.conf['site']['network'] ||= {})['assume_https'] = enabled
  Onetime::Middleware::AssumeHttps.new(MockApp.new)
end


## (a) HTTP request + secure:true + assume_https OFF => cookie NOT persisted
## security_matches? returns false, so commit_session bails before Set-Cookie.
reset_warn_guard!
req = request_for({}) # plain HTTP: no HTTPS env, no XFP => ssl? false
@session.send(:security_matches?, req, { secure: true })
#=> false

## (a2) ...and the Part 2 dropped-secure-cookie warning fired exactly once
CAPTURED_WARNINGS.length
#=> 1

## (a3) ...and the warning message names the actionable remediation
CAPTURED_WARNINGS.first.include?('ASSUME_HTTPS=true') &&
  CAPTURED_WARNINGS.first.include?('secure cookie')
#=> true

## (a4) ...and the warning carries the scheme-evidence snapshot as its own proof:
## for a plain HTTP request every scheme signal is absent and the scheme is nil.
reset_warn_guard!
@session.send(:security_matches?, request_for({}), { secure: true })
CAPTURED_PAYLOADS.first
#=> { rack_url_scheme: nil, x_forwarded_proto: false, forwarded: false, x_forwarded_ssl: false, https: false }

## (a5) ...and a present-but-non-https X-Forwarded-Proto is recorded as PRESENT
## in the evidence (it reached Rack but did not carry https) => pinpoints the hop
## without us reconstructing it. Rack still resolves scheme http, so ssl? false.
reset_warn_guard!
partial = request_for({ 'HTTP_X_FORWARDED_PROTO' => 'http' })
@session.send(:security_matches?, partial, { secure: true })
[partial.ssl?, CAPTURED_PAYLOADS.first[:x_forwarded_proto], CAPTURED_PAYLOADS.first[:https]]
#=> [false, true, false]

## (b) assume_https ON upgrades the scheme (Part 1): plain HTTP env is marked HTTPS
@env = {}
assume_https_middleware(true).call(@env)
[@env['HTTPS'], @env['rack.url_scheme']]
#=> ['on', 'https']

## (b2) ...so the upgraded request is now seen as SSL
request_for(@env).ssl?
#=> true

## (b3) ...and security_matches? now returns true => session PERSISTS (Set-Cookie)
reset_warn_guard!
result = @session.send(:security_matches?, request_for(@env), { secure: true })
[result, CAPTURED_WARNINGS.length]
#=> [true, 0]

## (c) REGRESSION PIN: X-Forwarded-Proto: https ALONE (no assume_https, no
## trusted_proxy config) is honored natively by Rack => request seen as SSL.
## Zero-config nginx/Caddy/ALB reverse-proxy behavior must not regress.
request_for({ 'HTTP_X_FORWARDED_PROTO' => 'https' }).ssl?
#=> true

## (c2) ...and that cookie persists (security_matches? true, no warn)
reset_warn_guard!
xfp_req = request_for({ 'HTTP_X_FORWARDED_PROTO' => 'https' })
result  = @session.send(:security_matches?, xfp_req, { secure: true })
[result, CAPTURED_WARNINGS.length]
#=> [true, 0]

## (d) UPGRADE-ONLY: assume_https OFF => AssumeHttps is a strict no-op; a plain
## HTTP request env is left completely untouched (no scheme mutation).
env = {}
assume_https_middleware(false).call(env)
[env.key?('HTTPS'), env.key?('rack.url_scheme')]
#=> [false, false]

## (d2) UPGRADE-ONLY: assume_https ON never DOWNGRADES an already-HTTPS request
## (X-Forwarded-Proto: https stays https; no rewrite/strip of forwarded scheme).
env = { 'HTTP_X_FORWARDED_PROTO' => 'https' }
assume_https_middleware(true).call(env)
request_for(env).ssl?
#=> true

# Restore the flag to its default OFF state for hygiene.
(OT.conf['site']['network'] ||= {})['assume_https'] = false
