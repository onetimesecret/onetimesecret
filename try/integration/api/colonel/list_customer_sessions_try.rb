# try/integration/api/colonel/list_customer_sessions_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel per-customer session LIST endpoint
# (spec docs/specs/colonel-ui/40-sessions-metadata-sidecar.md):
#
#   GET /api/colonel/users/:user_id/sessions
#
# The HTTP boundary over {Onetime::Operations::Sessions::ListForCustomer} — the
# O(sessions-for-this-user) sidecar read (no scan, no decrypt). `:user_id` is the
# customer's extid. Covers:
# - 403 for non-colonel, 401 for anonymous (dual-gate: router role=colonel AND
#   the logic's verify_one_of_roles!)
# - 200 with both seeded sessions, NEWEST-FIRST (active_sessions score desc)
# - each row is the safe_dump allow-list shape: user_id present, and NO
#   email / token / decrypted-payload key (the allow-list is the security boundary)
# - F-01: rows identify a session by session_handle (a non-bearer digest), and the
#   raw sid (== live cookie / blob key) appears NOWHERE in the response
# - an unknown user_id returns 200 with an empty list + count 0 (no raise)
#
# Sessions are seeded through the REAL write path (TrackMetadata) with a REAL
# encrypted blob minted per sid, so the op's blob-liveness probe sees them alive.
#
# Run: try --agent try/integration/api/colonel/list_customer_sessions_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry
require 'onetime/operations/sessions/track_metadata'

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i
@nonce     = Familia.generate_id[0, 12]
@codec     = Onetime::SessionCodec.from_config

@colonel = Onetime::Customer.create!(email: "colonel_lcs_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_lcs_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

# The customer whose sessions the colonel lists.
@target = Onetime::Customer.create!(email: "target_lcs_#{@timestamp}@example.com")
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

# Seed two sessions on @target, oldest first with ascending scores so newest-first
# ordering is observable. Mint a real encrypted blob per sid so the op's
# blob-liveness reconcile (EXISTS probe) keeps the row.
@sid_old = "intlcs_old_#{@nonce}"
@sid_new = "intlcs_new_#{@nonce}"
[@sid_old, @sid_new].each { |s| Onetime::SessionMetadata.load(s)&.destroy!; Familia.dbclient.del("session:#{s}") }

def seed(target, sid, score)
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => target.extid,
                    'ip_address' => '203.0.113.1', 'user_agent' => 'UA' },
  ).call
  Familia.dbclient.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                                        'external_id' => target.extid }))
  target.active_sessions.add(sid, score)
end

seed(@target, @sid_old, @timestamp)
seed(@target, @sid_new, @timestamp + 100)

URL = "/api/colonel/users/#{@extid}/sessions"

# --- Authorization -------------------------------------------------------

## Non-colonel gets 403
get URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401
@test.clear_cookies
get URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# --- List newest-first via safe_dump -------------------------------------

## 200 with both sessions, newest (highest score) first, count 2. Rows are keyed
## by session_handle (non-bearer digest), NOT the raw sid (F-01).
get URL, {}, colonel_headers
@resp = JSON.parse(last_response.body)
@d    = @resp['details']
[last_response.status, @d['count'], @d['sessions'].map { |s| s['session_handle'] }]
#=> [200, 2, [Onetime::SessionMetadata.handle_for(@sid_new), Onetime::SessionMetadata.handle_for(@sid_old)]]

## F-01: the raw sid (== live cookie value / `session:<sid>` blob key) appears
## NOWHERE in the response body — only the non-reversible handle crosses the wire
[last_response.body.include?(@sid_new), last_response.body.include?(@sid_old)]
#=> [false, false]

## details carries current_session_handle — the digest of the acting colonel's OWN
## request sid so the UI can badge their own row WITHOUT the response exposing the
## colonel's own live cookie either. It's a 32-hex handle, never the 64-hex sid.
@chandle = @d['current_session_handle']
[@d.key?('current_session_handle'), @chandle.is_a?(String), @chandle.match?(/\A[a-f0-9]{32}\z/) ? true : false]
#=> [true, true, true]

## each row is the safe_dump allow-list shape: user_id == target extid
@row = @d['sessions'].first
[@row['user_id'], @row['ip_address'], @row['user_agent']]
#=> ["#{@extid}", '203.0.113.1', 'UA']

## the row carries NO email, NO token, NO decrypted-payload key (security boundary)
## and NO raw session_id — the bearer sid is replaced by session_handle (F-01)
[@row.key?('email'), @row.key?('token'), @row.key?('authenticated'), @row.key?('external_id'), @row.key?('session_id')]
#=> [false, false, false, false, false]

## the row exposes exactly the safe_dump keys and nothing more
@row.keys.sort
#=> ["auth_method", "created_at", "geo_country", "ip_address", "last_activity_at", "mfa_used", "org_id", "session_handle", "user_agent", "user_id"]

# --- Unknown user_id -----------------------------------------------------

## an unknown user_id returns 200 with an empty list + count 0 (no raise)
get "/api/colonel/users/ur_nobody_#{@nonce}/sessions", {}, colonel_headers
@resp2 = JSON.parse(last_response.body)
[last_response.status, @resp2['details']['count'], @resp2['details']['sessions']]
#=> [200, 0, []]

# --- Teardown ------------------------------------------------------------
[@sid_old, @sid_new].each { |s| Onetime::SessionMetadata.load(s)&.destroy!; Familia.dbclient.del("session:#{s}") }
@target.active_sessions.clear
@colonel.destroy! rescue nil
@regular.destroy! rescue nil
@target.destroy!  rescue nil
