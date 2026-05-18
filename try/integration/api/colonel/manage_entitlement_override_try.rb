# try/integration/api/colonel/manage_entitlement_override_try.rb
#
# frozen_string_literal: true

# Integration tests for colonel entitlement override API endpoints:
#
#   POST   /api/colonel/organizations/:org_id/entitlements/grant
#   POST   /api/colonel/organizations/:org_id/entitlements/revoke
#   DELETE /api/colonel/organizations/:org_id/entitlements/overrides
#
# Covers:
# - Grant adds to entitlements_grants and calls reconciler
# - Revoke adds to entitlements_revokes and calls reconciler
# - Clear removes all grants and revokes
# - 403 for non-colonel users
# - 404 for non-existent org
# - 400 for missing entitlement param on grant/revoke
# - Response includes effective entitlements after operation
# - Unknown entitlement on grant succeeds (intentional)
#
# Run: try --agent try/integration/api/colonel/manage_entitlement_override_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

# Create test instance with Rack::Test::Methods
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# Delegate Rack::Test methods to @test
def post(*args);    @test.post(*args);    end
def get(*args);     @test.get(*args);     end
def delete(*args);  @test.delete(*args);  end
def last_response;  @test.last_response;  end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

# Colonel user (must have role='colonel' persisted so session auth reads it)
@colonel = Onetime::Customer.create!(email: "colonel_eo_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

# Regular (non-colonel) customer
@regular = Onetime::Customer.create!(email: "regular_eo_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

# Target organization with materialized entitlements
@org_owner = Onetime::Customer.create!(email: "org_owner_eo_#{@timestamp}@example.com")
@org_owner.verified = 'true'
@org_owner.save

@org = Onetime::Organization.create!("Entitlement Override Test Org #{@timestamp}", @org_owner, @org_owner.email)

# Materialize a baseline set of entitlements so grants/revokes have context
@org.entitlements_plan.add('api_access')
@org.entitlements_plan.add('create_secrets')
@org.materialized_entitlements_at = "#{@timestamp}:baseline"
@org.apply_entitlements
@org.save

# Sessions
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

# ----------------------------------------------------------------
# Authorization
# ----------------------------------------------------------------

## Non-colonel gets 403 on grant
post "/api/colonel/organizations/#{@org.objid}/entitlements/grant",
  { entitlement: 'custom_domains' }.to_json,
  { 'rack.session' => @regular_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous (no session) gets 302 redirect on grant
@test.clear_cookies
post "/api/colonel/organizations/#{@org.objid}/entitlements/grant",
  { entitlement: 'custom_domains' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status
#=> 302

# ----------------------------------------------------------------
# 404 for non-existent org
# ----------------------------------------------------------------

## Colonel gets 404 when org does not exist
post "/api/colonel/organizations/nonexistent_org_#{@timestamp}/entitlements/grant",
  { entitlement: 'custom_domains' }.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
[last_response.status, JSON.parse(last_response.body).key?('error')]
#=> [404, true]

# ----------------------------------------------------------------
# Grant entitlement
# ----------------------------------------------------------------

## Grant: returns 200 with expected structure
post "/api/colonel/organizations/#{@org.objid}/entitlements/grant",
  { entitlement: 'custom_domains' }.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[
  last_response.status,
  resp.key?('record'),
  resp['record']['action'],
  resp['record'].key?('effective_entitlements'),
  resp['record'].key?('grants'),
  resp['record'].key?('revokes'),
]
#=> [200, true, 'granted', true, true, true]

## Grant: granted entitlement appears in grants list
resp = JSON.parse(last_response.body)
resp['record']['grants'].include?('custom_domains')
#=> true

## Grant: granted entitlement appears in effective_entitlements
resp = JSON.parse(last_response.body)
resp['record']['effective_entitlements'].include?('custom_domains')
#=> true

## Grant: org has the grant persisted in Redis after request
@org_reloaded = Onetime::Organization.load(@org.objid)
@org_reloaded.entitlements_grants.member?('custom_domains')
#=> true

## Grant: unknown entitlement succeeds (intentional, for future entitlements)
post "/api/colonel/organizations/#{@org.objid}/entitlements/grant",
  { entitlement: 'future_feature_xyz' }.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['action']]
#=> [200, 'granted']

# ----------------------------------------------------------------
# Revoke entitlement
# ----------------------------------------------------------------

## Revoke: returns 200 with action='revoked'
post "/api/colonel/organizations/#{@org.objid}/entitlements/revoke",
  { entitlement: 'api_access' }.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['action']]
#=> [200, 'revoked']

## Revoke: revoked entitlement appears in revokes list
resp = JSON.parse(last_response.body)
resp['record']['revokes'].include?('api_access')
#=> true

## Revoke: revoked entitlement absent from effective_entitlements
resp = JSON.parse(last_response.body)
resp['record']['effective_entitlements'].include?('api_access')
#=> false

## Revoke: org has the revoke persisted in Redis after request
@org_reloaded = Onetime::Organization.load(@org.objid)
@org_reloaded.entitlements_revokes.member?('api_access')
#=> true

## Grant after revoke: removes from revokes and adds to grants (reciprocal)
post "/api/colonel/organizations/#{@org.objid}/entitlements/grant",
  { entitlement: 'api_access' }.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[resp['record']['revokes'].include?('api_access'), resp['record']['grants'].include?('api_access')]
#=> [false, true]

# ----------------------------------------------------------------
# Missing entitlement param
# ----------------------------------------------------------------

## Grant without entitlement param returns 400
post "/api/colonel/organizations/#{@org.objid}/entitlements/grant",
  {}.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 400

## Revoke without entitlement param returns 400
post "/api/colonel/organizations/#{@org.objid}/entitlements/revoke",
  {}.to_json,
  { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 400

# ----------------------------------------------------------------
# Clear overrides
# ----------------------------------------------------------------

## Clear: returns 200 with action='cleared'
delete "/api/colonel/organizations/#{@org.objid}/entitlements/overrides",
  {},
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['action']]
#=> [200, 'cleared']

## Clear: grants list is empty after clear
resp = JSON.parse(last_response.body)
resp['record']['grants']
#=> []

## Clear: revokes list is empty after clear
resp = JSON.parse(last_response.body)
resp['record']['revokes']
#=> []

## Clear: grants and revokes absent from Redis after clear
@org_reloaded = Onetime::Organization.load(@org.objid)
[@org_reloaded.entitlements_grants.size, @org_reloaded.entitlements_revokes.size]
#=> [0, 0]

## Clear: response includes effective_entitlements (plan baseline remains)
resp = JSON.parse(last_response.body)
resp['record']['effective_entitlements'].is_a?(Array)
#=> true

## Non-colonel gets 403 on revoke
post "/api/colonel/organizations/#{@org.objid}/entitlements/revoke",
  { entitlement: 'api_access' }.to_json,
  { 'rack.session' => @regular_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Non-colonel gets 403 on clear
delete "/api/colonel/organizations/#{@org.objid}/entitlements/overrides",
  {},
  { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
@org.destroy!       rescue nil
@org_owner.destroy! rescue nil
@colonel.destroy!   rescue nil
@regular.destroy!   rescue nil
