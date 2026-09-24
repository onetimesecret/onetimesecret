# try/integration/api/colonel/elevation_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel step-up (sudo) window (#4327):
#
#   GET    /api/colonel/elevation
#   POST   /api/colonel/elevation
#   DELETE /api/colonel/elevation
#
# The whole loop over real Rack, in AUTHENTICATION_MODE=simple: attempt a TIER 1
# verb with nothing but a colonel session, get 403 elevation_required, elevate
# with the account password, retry the verb WITH the #4326 confirmation header,
# succeed, drop the window, and be refused again. That sequence is the epic's
# definition of done for this issue — "a colonel session alone is no longer
# sufficient for destruction" — and it is only provable end to end.
#
# It also pins the two orderings the unit specs cannot see from inside one class:
#
#   - elevation is checked BEFORE confirmation, so an unelevated caller sending a
#     wrong token still gets elevation_required and no confirmation oracle;
#   - a failed step-up writes a SECURITY audit event and the successful one
#     writes an operator event carrying the factor, while the ElevationRequired
#     refusal writes NOTHING (a cookie holder could otherwise mint events on
#     demand into a count-capped, TTL-less trail).
#
# Elevation ships ENABLED but spec/config.test.yaml disables it for suite
# hygiene, so this file turns it on in-process and restores OT.conf in teardown
# (tryout files share one process and one global config).
#
# Run: try --agent try/integration/api/colonel/elevation_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def post(*args);   @test.post(*with_csrf(args));   end
def delete(*args); @test.delete(*with_csrf(args)); end
def get(*args);    @test.get(*args);               end
def last_response; @test.last_response;            end
def body;          JSON.parse(@test.last_response.body); end

AE = Onetime::ColonelAuditEvent

@saved_conf = YAML.load(YAML.dump(OT.conf))

def set_elevation(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['admin'] ||= {}
  new_conf['site']['admin']['elevation'] = cfg
  OT.send(:conf=, new_conf)
end

set_elevation('enabled' => true, 'window' => 600, 'reauth_grace' => 0)

@timestamp = Familia.now.to_i
@password  = "elevate-me-#{@timestamp}"

@colonel = Onetime::Customer.create!(email: "colonel_elev_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save
@colonel.update_passphrase!(@password)

@target = Onetime::Customer.create!(email: "target_elev_#{@timestamp}@example.com")
@target.verified = 'true'
@target.save

@regular = Onetime::Customer.create!(email: "regular_elev_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

# Seeds the authenticated colonel identity into each request. The session
# MIDDLEWARE owns the hash the logic classes actually read and write (and
# persists it across requests through the cookie jar), so assertions about what
# elevation stored read @test.last_request.env['rack.session'], not this seed.
@sess = {
  'authenticated' => true,
  'external_id' => @colonel.extid,
  'email' => @colonel.email,
  'authenticated_at' => Familia.now.to_i,
}

def colonel_headers
  { 'rack.session' => @sess, 'HTTP_ACCEPT' => 'application/json' }
end

# TIER 1 verb under test: revoking all of a customer's sessions. Its #4326
# confirmation token is the target's EMAIL, an identifier the URL never carries.
def confirming_headers
  colonel_headers.merge('HTTP_X_OTS_CONFIRM' => Rack::Utils.escape(@target.email))
end

ELEVATION_URL = '/api/colonel/elevation'

def revoke_all_url
  "/api/colonel/users/#{@target.extid}/sessions/revoke-all"
end

# --- Authorization on the elevation endpoints themselves ------------------

## A non-colonel cannot read elevation status
@test.clear_cookies
get ELEVATION_URL, {}, { 'rack.session' => { 'authenticated' => true,
                                             'external_id' => @regular.extid,
                                             'email' => @regular.email },
                         'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## An anonymous caller gets 401
@test.clear_cookies
get ELEVATION_URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# --- The unelevated colonel ----------------------------------------------

## Status starts at "not elevated", and reports the configured window
@test.clear_cookies
get ELEVATION_URL, {}, colonel_headers
[last_response.status, body['record']['elevated'], body['details']['enabled'], body['details']['window']]
#=> [200, false, true, 600]

## The account has a password, so `password` is the only offered factor
[body['details']['password_available'], body['details']['factors']]
#=> [true, ["password"]]

## A TIER 1 verb refuses with 403 elevation_required — a colonel session and the
## correct confirmation token are together NOT sufficient
AE.events.clear
post revoke_all_url, {}, confirming_headers
[last_response.status, body['error_type'], body['error_code'], body['window']]
#=> [403, "ElevationRequired", "elevation_required", 600]

## That refusal writes NO audit event: it is drivable on demand by whoever holds
## the cookie, and the operator trail is count-capped with no TTL
AE.count
#=> 0

## Elevation is checked BEFORE confirmation, so a WRONG token still answers
## elevation_required — no confirmation oracle for an unelevated caller
post revoke_all_url, {}, colonel_headers.merge('HTTP_X_OTS_CONFIRM' => 'not-the-token')
[last_response.status, body['error_code']]
#=> [403, "elevation_required"]

# --- Elevating -----------------------------------------------------------

## A wrong password is 403 elevation_failed, and grants nothing
AE.security_events.clear
post ELEVATION_URL, { 'factor' => 'password', 'password' => 'wrong-password' }, colonel_headers
[last_response.status, body['error_type'], body['error_code'],
 @test.last_request.env['rack.session'].key?('elevated_until')]
#=> [403, "ElevationFailed", "elevation_failed", false]

## The failure is recorded as a SECURITY event, not on the operator trail
[AE.security_count, AE.count]
#=> [1, 0]

## `recent_auth` is refused for an account that HAS a password, even one second
## after sign-in — the B-3 lock, live over HTTP
post ELEVATION_URL, { 'factor' => 'recent_auth' }, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "elevation_failed"]

## An unknown factor is a 422, not a 403
post ELEVATION_URL, { 'factor' => 'telepathy' }, colonel_headers
last_response.status
#=> 422

## The right password mints a window
AE.events.clear
post ELEVATION_URL, { 'factor' => 'password', 'password' => @password }, colonel_headers
[last_response.status, body['record']['elevated'], body['details']['factor'], body['details']['window']]
#=> [200, true, "password", 600]

## What landed IN THE SESSION is an identity-bound object, never a bare epoch.
## Read through the request Rack actually served: the session middleware owns
## the hash the logic class wrote to, not the seed hash passed in the env.
@stored = @test.last_request.env['rack.session']['elevated_until']
[@stored.is_a?(Hash), @stored['extid'], @stored['exp'] > Familia.now.to_i]
#=> [true, @colonel.extid, true]

## Exactly one colonel.elevate event, carrying the FACTOR so the weaker path
## would be visible in the trail
@ev = AE.recent(1).first
[AE.count, @ev['verb'], @ev['actor'], @ev['target']]
#=> [1, "colonel.elevate", "#{@colonel.extid}", "#{@colonel.extid}"]

## Status now reports the live window with a countdown seed
get ELEVATION_URL, {}, colonel_headers
[last_response.status, body['record']['elevated'], body['record']['seconds_remaining'].positive?]
#=> [200, true, true]

# --- The elevated colonel ------------------------------------------------

## The TIER 1 verb now succeeds — with the confirmation header still required
AE.events.clear
post revoke_all_url, {}, confirming_headers
[last_response.status, body['record']['revoked']]
#=> [200, true]

## Elevation does NOT replace confirmation: the same elevated session without
## the header is still 403, now on the confirmation gate
post revoke_all_url, {}, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "confirmation_required"]

# --- Dropping ------------------------------------------------------------

## DELETE ends the window
AE.events.clear
delete ELEVATION_URL, {}, colonel_headers
[last_response.status, body['record']['elevated'],
 @test.last_request.env['rack.session'].key?('elevated_until')]
#=> [200, false, false]

## ...and it is audited as the closing half of the bracket
[AE.count, AE.recent(1).first['verb']]
#=> [1, "colonel.elevate_drop"]

## The TIER 1 verb is refused again
post revoke_all_url, {}, confirming_headers
[last_response.status, body['error_code']]
#=> [403, "elevation_required"]

# --- Disabled by config --------------------------------------------------

## With elevation disabled the tier-1 verb runs on confirmation alone — the
## pre-#4327 posture, which is what enabled:false is for
set_elevation('enabled' => false)
post revoke_all_url, {}, confirming_headers
last_response.status
#=> 200

## ...and the elevation endpoint refuses to mint a window at all
post ELEVATION_URL, { 'factor' => 'password', 'password' => @password }, colonel_headers
last_response.status
#=> 422

# Restore the shared config for later tryout files.
OT.send(:conf=, @saved_conf)
