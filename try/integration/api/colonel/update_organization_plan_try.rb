# try/integration/api/colonel/update_organization_plan_try.rb
#
# frozen_string_literal: true

# Integration tests for the org-level plan change:
#
#   POST /api/colonel/organizations/:org_id/plan
#
# The org-level successor to POST /users/:user_id/plan — the billing
# relationship (Stripe ids, subscription state, the entitlement engine) lives
# on Organization, so the admin plan control operates on the org. Thin adapter
# over Onetime::Operations::Org::SetPlan, which owns the mutation AND the
# single ColonelAuditEvent (verb organization.set_plan).
#
# Covers:
# - happy path by extid: planid written, changed:true, old/new echoed
# - resolution by internal objid (extid-then-objid, like the other org verbs)
# - idempotent no-op: changed:false, no second audit event
# - catalog validation: an unknown planid is a 4xx, nothing written
# - authorization: non-colonel gets no joy
# - exactly-one audit event per successful change
#
# Run: try --agent try/integration/api/colonel/update_organization_plan_try.rb

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
def last_response; @test.last_response; end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_uop_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@owner = Onetime::Customer.create!(email: "owner_uop_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

@org = Onetime::Organization.create!(
  "Plan Change Org #{@timestamp}", @owner, "org_uop_#{@timestamp}@example.com"
)
@org.planid = 'free'
@org.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}

@owner_session = {
  'authenticated' => true,
  'external_id'   => @owner.extid,
  'email'         => @owner.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

def owner_headers
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
end

def change_plan(org_id, planid, headers = colonel_headers)
  post "/api/colonel/organizations/#{org_id}/plan", { 'planid' => planid }, headers
  last_response
end

def audit_count_for(org_extid)
  Onetime::ColonelAuditEvent.recent(500).count do |event|
    event['verb'] == 'organization.set_plan' && event['target'] == org_extid
  end
end

# ----------------------------------------------------------------
# Happy path (extid)
# ----------------------------------------------------------------

## Changing the plan by org EXTID succeeds and echoes old/new planids
change_plan(@org.extid, 'free_v1')
@body = JSON.parse(last_response.body)
[
  last_response.status,
  @body['record']['old_planid'],
  @body['record']['new_planid'],
  @body['details']['changed'],
]
#=> [200, 'free', 'free_v1', true]

## The planid actually persisted on the organization
Onetime::Organization.load(@org.objid).planid
#=> 'free_v1'

## Exactly ONE audit event was recorded for the change
audit_count_for(@org.extid)
#=> 1

## No Stripe subscription on this org -> no overwrite warning
@body['details']['warning']
#=> nil

# ----------------------------------------------------------------
# Idempotent no-op
# ----------------------------------------------------------------

## Re-applying the same plan is a 200 no-op (changed: false)
change_plan(@org.extid, 'free_v1')
JSON.parse(last_response.body)['details']['changed']
#=> false

## The no-op recorded NO additional audit event (nothing mutated)
audit_count_for(@org.extid)
#=> 1

# ----------------------------------------------------------------
# Resolution by objid
# ----------------------------------------------------------------

## The org resolves by internal OBJID too (extid-then-objid, like every org verb)
change_plan(@org.objid, 'free')
@body_objid = JSON.parse(last_response.body)
[last_response.status, @body_objid['record']['extid'], @body_objid['details']['changed']]
#=> [200, @org.extid, true]

# ----------------------------------------------------------------
# Validation + authorization
# ----------------------------------------------------------------

## An unknown planid is rejected by catalog validation (4xx, nothing written)
change_plan(@org.extid, "bogus_plan_#{@timestamp}")
[last_response.status >= 400, Onetime::Organization.load(@org.objid).planid]
#=> [true, 'free']

## An unknown org identifier 404s
change_plan("or_does_not_exist_#{@timestamp}", 'free_v1')
last_response.status
#=> 404

## A non-colonel caller cannot change an org's plan
change_plan(@org.extid, 'free_v1', owner_headers)
[last_response.status >= 400, Onetime::Organization.load(@org.objid).planid]
#=> [true, 'free']

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------

begin
  @org.destroy!
rescue StandardError
  nil
end
[@colonel, @owner].each do |cust|
  cust.destroy!
rescue StandardError
  nil
end
