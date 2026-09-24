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

# The adapter's message/problem qualification keyed off the op's
# materialization + cascade outcome, exercised directly (the engine's failure
# paths can't be triggered through the HTTP stack without breaking the
# billing engine mid-request).
def adapter_for(materialization, memberships: nil)
  logic = ColonelAPI::Logic::Colonel::UpdateOrganizationPlan.allocate
  logic.instance_variable_set(:@new_planid, 'team_plus_v1')
  logic.instance_variable_set(:@result, Onetime::Operations::Org::SetPlan::Result.new(
    status: :success, org: nil, from: 'free', to: 'team_plus_v1',
    materialization: materialization, memberships: memberships,
  ))
  logic
end

def adapter_message_for(materialization, memberships: nil)
  adapter_for(materialization, memberships: memberships).send(:message)
end

def adapter_problem_for(materialization, memberships: nil)
  adapter_for(materialization, memberships: memberships).send(:entitlement_problem?)
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

## The materialization outcome is reported, and with nothing degraded the
## message is the unqualified success line with entitlements_ok true
[
  @body['details']['materialization'].is_a?(String),
  @body['details']['entitlements_ok'],
  @body['details'].key?('memberships'),
  @body['details']['message'],
]
#=> [true, true, true, 'Organization plan updated successfully']

## An engine failure mid-materialize yields a QUALIFIED message pointing at
## reconcile — never the unqualified success line (the planid wrote but the
## org keeps the previous plan's entitlements)
@failed_msg = adapter_message_for(:materialization_failed)
[@failed_msg.include?('re-materialization failed'), @failed_msg.include?('reconcile')]
#=> [true, true]

## A planid the catalog can't materialize (e.g. 'free' vs the shipped
## 'free_v1') is likewise qualified: entitlements were NOT updated
adapter_message_for(:plan_not_found).include?('entitlements were NOT updated')
#=> true

## The standalone skip is not a problem status: billing-disabled installs
## legitimately write the field alone
[adapter_message_for(:skipped_standalone), adapter_problem_for(:skipped_standalone)]
#=> ['Organization plan updated successfully', false]

## A PARTIAL membership cascade (engine returns :materialized with failed
## counts) is qualified and flagged: those members keep the previous plan's
## entitlements
@partial = { success: 3, failed: 2, total: 5, failed_ids: %w[m1 m2] }
@partial_msg = adapter_message_for(:materialized, memberships: @partial)
[
  @partial_msg.include?('2 of 5'),
  @partial_msg.include?('reconcile'),
  adapter_problem_for(:materialized, memberships: @partial),
]
#=> [true, true, true]

## A cascade that RAISED (nil memberships on :materialized — the engine's
## documented unobserved-outcome signal) is likewise qualified and flagged
[
  adapter_message_for(:materialized).include?('did not complete'),
  adapter_problem_for(:materialized),
]
#=> [true, true]

## A clean cascade on :materialized is an unqualified success
@clean = { success: 5, failed: 0, total: 5, failed_ids: [] }
[
  adapter_message_for(:materialized, memberships: @clean),
  adapter_problem_for(:materialized, memberships: @clean),
]
#=> ['Organization plan updated successfully', false]

## A RAISING BillingConfig on the op lands in :materialization_failed — never
## the clean standalone skip WithEntitlements#billing_enabled? would rescue
## it into (which would report entitlements_ok on a commercial deployment
## whose entitlements silently kept the previous plan)
@op = Onetime::Operations::Org::SetPlan.new(
  org: @org, planid: 'free_v1', actor: @colonel.extid,
)
@orig_instance = Onetime::BillingConfig.method(:instance)
Onetime::BillingConfig.define_singleton_method(:instance) { raise StandardError, 'config boom' }
begin
  @broken_state = @op.send(:billing_state)
  @broken_mat   = @op.send(:materialize_entitlements)
ensure
  Onetime::BillingConfig.define_singleton_method(:instance, @orig_instance)
end
[@broken_state, @broken_mat]
#=> [:unavailable, [:materialization_failed, nil]]

# ----------------------------------------------------------------
# Idempotent no-op
# ----------------------------------------------------------------

## Re-applying the same plan is a 200 no-op (changed: false)
change_plan(@org.extid, 'free_v1')
JSON.parse(last_response.body)['details']['changed']
#=> false

## The no-op DOES record an audit event now (#4337): nothing mutated, but an
## operator deliberately moved this org onto a plan and that attempt belongs in
## the trail — marked outcome: no_change rather than dropped.
audit_count_for(@org.extid)
#=> 2

## …under the same verb, marked as a no-change attempt
Onetime::ColonelAuditEvent.recent(1).first['detail']
#=> { "outcome" => "no_change", "from" => "free_v1", "to" => "free_v1" }

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
