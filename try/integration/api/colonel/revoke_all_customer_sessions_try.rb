# try/integration/api/colonel/revoke_all_customer_sessions_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel per-customer REVOKE-ALL endpoint
# (spec docs/specs/colonel-ui/40-sessions-metadata-sidecar.md):
#
#   POST /api/colonel/users/:user_id/sessions/revoke-all
#
# The HTTP boundary over {Onetime::Operations::Sessions::RevokeAllForCustomer} —
# the offboarding / takeover variant. Real encrypted blobs are minted (tracked +
# an UNTRACKED pre-sidecar blob), so the total kill is genuine, not mocked. It is
# a POST+verb route (bulk-destructive convention) that must NOT collide with the
# single-revoke DELETE. Covers:
# - 403 for non-colonel, 401 for anonymous (dual-gate)
# - a successful POST returns record.revoked=true with kill counts; every one of
#   the customer's live blobs is GONE (tracked AND untracked), the sidecars are
#   destroyed, and Customer#active_sessions is cleared
# - a DIFFERENT customer's session is untouched
# - EXACTLY ONE AdminAuditEvent (verb 'session.revoke_all', target = the extid)
#
# Run: try --agent try/integration/api/colonel/revoke_all_customer_sessions_try.rb

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

def post(*args);   @test.post(*with_csrf(args));   end
def last_response; @test.last_response; end

Store = Onetime::Operations::Sessions::Store
SM    = Onetime::SessionMetadata
AE    = Onetime::AdminAuditEvent
DB    = Familia.dbclient

@timestamp = Familia.now.to_i
@nonce     = Familia.generate_id[0, 12]
@codec     = Onetime::SessionCodec.from_config

@colonel = Onetime::Customer.create!(email: "colonel_racs_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_racs_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@target = Onetime::Customer.create!(email: "target_racs_#{@timestamp}@example.com")
@target.verified = 'true'
@target.save
@extid = @target.extid

@other = Onetime::Customer.create!(email: "other_racs_#{@timestamp}@example.com")
@other.verified = 'true'
@other.save

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

# Two tracked blobs + one untracked (pre-sidecar) blob for the target.
@tracked = ["intracs_a_#{@nonce}", "intracs_b_#{@nonce}"]
@tracked.each do |sid|
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => @extid,
                    'ip_address' => '203.0.113.2', 'user_agent' => 'UA' },
  ).call
  DB.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                           'external_id' => @extid, 'email' => @target.email }))
end
@untracked = "intracs_untracked_#{@nonce}"
DB.set("session:#{@untracked}", @codec.encode({ 'authenticated' => true,
                                                'external_id' => @extid, 'email' => @target.email }))
@other_sid = "intracs_other_#{@nonce}"
DB.set("session:#{@other_sid}", @codec.encode({ 'authenticated' => true,
                                               'external_id' => @other.extid, 'email' => @other.email }))

URL = "/api/colonel/users/#{@extid}/sessions/revoke-all"

# --- Authorization -------------------------------------------------------

## Non-colonel gets 403 (and the sessions survive)
post URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
[last_response.status, Store.find_key(DB, @tracked[0]).nil?]
#=> [403, false]

## Anonymous gets 401 (and the sessions survive)
@test.clear_cookies
post URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
[last_response.status, Store.find_key(DB, @tracked[0]).nil?]
#=> [401, false]

# --- Revoke-all: total kill + tidy + audit -------------------------------

## POST by the colonel returns 200 with revoked=true and a kill count of 3
AE.events.clear
post URL, {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['record']['revoked'], @resp['record']['blobs_deleted'], @resp['record']['untracked_deleted']]
#=> [200, true, 3, 1]

## every one of the target's live blobs is GONE (tracked and untracked)
[Store.find_key(DB, @tracked[0]), Store.find_key(DB, @tracked[1]), Store.find_key(DB, @untracked)]
#=> [nil, nil, nil]

## the OTHER customer's session is untouched
Store.find_key(DB, @other_sid).nil?
#=> false

## the sidecars are destroyed and the customer index is cleared
[SM.load(@tracked[0]).nil?, SM.load(@tracked[1]).nil?, @target.active_sessions.revrange(0, -1)]
#=> [true, true, []]

## EXACTLY ONE audit event: verb session.revoke_all, target the extid, actor the colonel
[AE.count, AE.recent(1).first['verb'], AE.recent(1).first['target'], AE.recent(1).first['actor']]
#=> [1, "session.revoke_all", "#{@extid}", "#{@colonel.extid}"]

# --- Teardown ------------------------------------------------------------
@tracked.each { |sid| SM.load(sid)&.destroy!; DB.del("session:#{sid}") }
DB.del("session:#{@untracked}")
DB.del("session:#{@other_sid}")
@target.active_sessions.clear
AE.events.clear
@colonel.destroy! rescue nil
@regular.destroy! rescue nil
@target.destroy!  rescue nil
@other.destroy!   rescue nil
