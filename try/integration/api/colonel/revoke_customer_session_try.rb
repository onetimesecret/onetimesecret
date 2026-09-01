# try/integration/api/colonel/revoke_customer_session_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel per-customer session REVOKE endpoint
# (spec docs/specs/colonel-ui/40-sessions-metadata-sidecar.md):
#
#   DELETE /api/colonel/users/:user_id/sessions/:session_handle
#
# The HTTP boundary over {Onetime::Operations::Sessions::RevokeForCustomer}. In
# this codebase a session dies by deleting the encrypted `session:<sid>` blob
# (adaptation #1), NOT by removing a Rodauth index row — so the blob is minted for
# real and the invalidation is genuine, not mocked.
#
# F-01: the endpoint accepts the non-bearer session_handle (a digest of the sid),
# NOT the raw sid — the raw sid is the live cookie / blob key and never leaves the
# server. The adapter resolves the handle back to a sid by matching it over the
# target customer's own active_sessions set. Covers:
# - 403 for non-colonel, 401 for anonymous (dual-gate)
# - a successful DELETE (by handle) returns record.revoked=true + echoes the
#   handle; the live blob is GONE, the sidecar is destroyed, and the sid is ZREM'd
# - the response NEVER carries the raw sid
# - EXACTLY ONE ColonelAuditEvent per revoke (verb 'session.revoke', target = the
#   target extid, actor = the acting colonel's extid)
# - a stale handle (session already revoked / no longer in the active set) is a 404
#
# Run: try --agent try/integration/api/colonel/revoke_customer_session_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry
require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/store'

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def delete(*args);  @test.delete(*with_csrf(args));  end
def last_response;  @test.last_response;  end

Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::ColonelAuditEvent
DB    = Familia.dbclient

@timestamp = Familia.now.to_i
@nonce     = Familia.generate_id[0, 12]
@codec     = Onetime::SessionCodec.from_config

@colonel = Onetime::Customer.create!(email: "colonel_rcs_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_rcs_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@target = Onetime::Customer.create!(email: "target_rcs_#{@timestamp}@example.com")
@target.verified = 'true'
@target.save
@extid = @target.extid

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}
@regular_session = {
  'authenticated' => true,
  'external_id'   => @regular.extid,
  'email'         => @regular.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

# Server-side destructive-action confirmation (#4326): revoking sessions is
# TIER 1, so it requires the account's email — percent-encoded — in
# X-OTS-Confirm. The URL carries the extid (and, for the single revoke, an
# opaque handle); the token is deliberately a different identifier.
def confirming_headers
  colonel_headers.merge('HTTP_X_OTS_CONFIRM' => Rack::Utils.escape(@target.email))
end

@sid = "intrcs_#{@nonce}"
@key = "session:#{@sid}"

def seed_session(target, sid)
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => target.extid,
                    'ip_address' => '203.0.113.2', 'user_agent' => 'UA' },
  ).call
  # Mint a REAL encrypted blob (the shape the app stores), so the revoke deletes
  # an actual key — the genuine logout.
  DB.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                          'external_id' => target.extid,
                                          'email' => target.email }))
  target.active_sessions.add(sid, @timestamp)
end

SM.load(@sid)&.destroy!
DB.del(@key)
seed_session(@target, @sid)

# The endpoint is keyed by the non-bearer handle (F-01), not the raw sid.
@handle = SM.handle_for(@sid)
URL = "/api/colonel/users/#{@extid}/sessions/#{@handle}"

# --- Authorization -------------------------------------------------------

## Non-colonel gets 403 (and the session survives)
delete URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
[last_response.status, Store.find_key(DB, @sid).nil?]
#=> [403, false]

## Anonymous gets 401 (and the session survives)
@test.clear_cookies
delete URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
[last_response.status, Store.find_key(DB, @sid).nil?]
#=> [401, false]

# --- Revoke: invalidate + tidy + audit -----------------------------------

## before revoke: the live blob, the sidecar, and the index member all exist
[Store.find_key(DB, @sid), SM.load(@sid).nil?, @target.active_sessions.member?(@sid)]
#=> [@key, false, true]

## DELETE by the colonel returns 200 with record.revoked=true and the HANDLE echoed
AE.events.clear
delete URL, {}, confirming_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['record']['revoked'], @resp['record']['session_handle'], @resp['details']['message']]
#=> [200, true, "#{@handle}", 'Session revoked successfully']

## F-01: the response body NEVER carries the raw sid (== live cookie / blob key)
last_response.body.include?(@sid)
#=> false

## the live `session:<sid>` blob is GONE (this is what logs the user out)
Store.find_key(DB, @sid)
#=> nil

## the sidecar is destroyed and the sid is ZREM'd from the customer index
[SM.load(@sid).nil?, @target.active_sessions.member?(@sid)]
#=> [true, false]

## EXACTLY ONE audit event: verb session.revoke, target the extid, actor the colonel
[AE.count, AE.recent(1).first['verb'], AE.recent(1).first['target'], AE.recent(1).first['actor']]
#=> [1, "session.revoke", "#{@extid}", "#{@colonel.extid}"]

## the audit detail carries the session id and no secret material
AE.recent(1).first['detail']['session_id']
#=> "#{@sid}"

# --- Stale handle: the resolved session is gone --------------------------

## a second DELETE with the now-stale handle 404s — the first revoke ZREM'd the
## sid from the active set, so the handle resolves to no session to revoke
AE.events.clear
delete URL, {}, confirming_headers
last_response.status
#=> 404

# --- Teardown ------------------------------------------------------------
SM.load(@sid)&.destroy!
DB.del(@key)
@target.active_sessions.clear
AE.events.clear
@colonel.destroy! rescue nil
@regular.destroy! rescue nil
@target.destroy!  rescue nil
