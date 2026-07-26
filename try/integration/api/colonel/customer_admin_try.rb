# try/integration/api/colonel/customer_admin_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel customer-admin mutation endpoints (epic #20):
#
#   POST   /api/colonel/users/:user_id/role       { role: '...' }
#   POST   /api/colonel/users/:user_id/verify
#   POST   /api/colonel/users/:user_id/unverify
#   DELETE /api/colonel/users/:user_id
#
# Covers:
# - Security invariant: 403 for non-colonel, 401 for anonymous (both-auth-layers)
# - 404 for a non-existent user
# - 422 for an invalid role
# - Success shape for each verb
# - Every mutation records exactly one AdminAuditEvent with actor = colonel extid
#
# Run: try --agent try/integration/api/colonel/customer_admin_try.rb

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
def post(*args);   @test.post(*args);   end
def get(*args);    @test.get(*args);    end
def delete(*args); @test.delete(*args); end
def last_response; @test.last_response; end

AE = Onetime::AdminAuditEvent

@ts = Familia.now.to_i

# Colonel actor (verified + role=colonel so session auth grants the role)
@colonel = Onetime::Customer.create!(email: "colonel_ca_#{@ts}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

# Non-colonel customer
@regular = Onetime::Customer.create!(email: "regular_ca_#{@ts}@example.com")
@regular.verified = 'true'
@regular.save

# Mutation targets
@role_target   = Onetime::Customer.create!(email: "roletarget_ca_#{@ts}@example.com")
@verify_target = Onetime::Customer.create!(email: "vtarget_ca_#{@ts}@example.com")
@verify_target.verified = 'false'
@verify_target.save
@purge_target  = Onetime::Customer.create!(email: "ptarget_ca_#{@ts}@example.com")
@purge_target_objid = @purge_target.objid

@colonel_session = { 'authenticated' => true, 'external_id' => @colonel.extid, 'email' => @colonel.email }
@regular_session = { 'authenticated' => true, 'external_id' => @regular.extid, 'email' => @regular.email }
# Session-authenticated non-GET requests require a valid X-CSRF-Token.
@colonel_headers = { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => tryouts_csrf_token(@colonel_session) }
@regular_headers = { 'rack.session' => @regular_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => tryouts_csrf_token(@regular_session) }

# ---- Authorization (both-auth-layers) ---------------------------------

## Non-colonel gets 403 on role change
post "/api/colonel/users/#{@role_target.objid}/role", { role: 'admin' }.to_json, @regular_headers
last_response.status
#=> 403

## Anonymous (no session) gets 401 on role change
@test.clear_cookies
post "/api/colonel/users/#{@role_target.objid}/role", { role: 'admin' }.to_json, { 'CONTENT_TYPE' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403 on purge (DELETE)
delete "/api/colonel/users/#{@role_target.objid}", {}, @regular_headers
last_response.status
#=> 403

# ---- 404 / 422 --------------------------------------------------------

## Colonel gets 404 for a non-existent user
post "/api/colonel/users/nonexistent_#{@ts}/role", { role: 'admin' }.to_json, @colonel_headers
last_response.status
#=> 404

## Colonel gets 422 for an invalid role
post "/api/colonel/users/#{@role_target.objid}/role", { role: 'wizard' }.to_json, @colonel_headers
last_response.status
#=> 422

# ---- Role change success + audit --------------------------------------

## Role change returns 200 with the expected record shape
AE.events.clear
post "/api/colonel/users/#{@role_target.objid}/role", { role: 'admin' }.to_json, @colonel_headers
@role_resp = JSON.parse(last_response.body)
[last_response.status, @role_resp['record']['new_role'], @role_resp['record']['old_role'], @role_resp['details']['changed']]
#=> [200, "admin", "customer", true]

## Role change persisted to Redis
Onetime::Customer.load(@role_target.objid).role
#=> "admin"

## Role change recorded exactly one audit event, actor = colonel extid
[AE.count, AE.recent(1).first['verb'], AE.recent(1).first['actor']]
#=> [1, "customer.set_role", @colonel.extid]

# ---- Verify / unverify success + audit --------------------------------

## Verify returns 200 and marks the user verified
AE.events.clear
post "/api/colonel/users/#{@verify_target.objid}/verify", {}.to_json, @colonel_headers
[last_response.status, Onetime::Customer.load(@verify_target.objid).verified?, AE.recent(1).first['verb']]
#=> [200, true, "customer.set_verification"]

## Unverify returns 200 and marks the user unverified
post "/api/colonel/users/#{@verify_target.objid}/unverify", {}.to_json, @colonel_headers
[last_response.status, Onetime::Customer.load(@verify_target.objid).verified?]
#=> [200, false]

# ---- Purge success + audit --------------------------------------------

## Purge (DELETE) returns 200, destroys the user, audits once
AE.events.clear
delete "/api/colonel/users/#{@purge_target.objid}", {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => tryouts_csrf_token(@colonel_session) }
@purge_resp = JSON.parse(last_response.body)
[last_response.status, @purge_resp['record']['deleted'], Onetime::Customer.load(@purge_target_objid).nil?, AE.count, AE.recent(1).first['verb']]
#=> [200, true, true, 1, "customer.purge"]

# ---- Teardown ---------------------------------------------------------
AE.events.clear
@colonel.destroy!       rescue nil
@regular.destroy!       rescue nil
@role_target.destroy!   rescue nil
@verify_target.destroy! rescue nil
