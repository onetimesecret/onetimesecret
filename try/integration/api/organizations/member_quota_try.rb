# try/integration/api/organizations/member_quota_try.rb
#
# frozen_string_literal: true

#
# Integration test for member quota entitlement checks
# Verifies that CreateInvitation enforces member limits per plan

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
def post(*args); @test.post(*args); end
def get(*args); @test.get(*args); end
def put(*args); @test.put(*args); end
def delete(*args); @test.delete(*args); end
def last_response; @test.last_response; end

# Setup: Create customer with organization
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "member_quota_owner_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

@org = Onetime::Organization.create!("Member Quota Test Org", @owner, @owner.email)
@org.is_default = true
@org.save

@session = { 'authenticated' => true, 'external_id' => @owner.extid, 'email' => @owner.email }

# Plan data used across all billing blocks
@limited_plan = {
  plan_id: 'limited_members',
  name: 'Limited Members Plan',
  tier: 'free',
  interval: 'month',
  region: 'us',
  entitlements: ['create_secrets'],
  limits: { 'members_per_team.max' => '3' }  # Limit: 3 total members
}

# Helper to run billing-enabled test and return results
def run_billing_test_invite(org, session, email, plan)
  result = { status: nil, error_type: nil, error_message: nil, record_id: nil, record_email: nil, member_count: nil, pending_count: nil }
  BillingTestHelpers.with_billing_enabled(plans: [plan]) do
    org.planid = plan[:plan_id]
    org.save
    org = Onetime::Organization.load(org.objid)

    # Capture counts before the API call
    result[:member_count] = org.member_count
    result[:pending_count] = org.pending_invitation_count

    post "/api/organizations/#{org.extid}/invitations",
      { email: email, role: 'member' }.to_json,
      { 'rack.session' => session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }

    result[:status] = last_response.status
    resp = JSON.parse(last_response.body)
    if result[:status] == 200
      result[:record_id] = resp['record']['id']
      result[:record_email] = resp['record']['email']
    else
      result[:error_type] = resp['error']
      result[:error_message] = resp['message']
    end
  end
  result
end

## Standalone mode: Can invite first member without limit (no billing)
post "/api/organizations/#{@org.extid}/invitations",
  { email: "member1_#{@timestamp}@example.com", role: 'member' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## First invitation created successfully
resp = JSON.parse(last_response.body)
@invite1_id = resp['record']['id']
resp['record']['email']
#=> "member1_#{@timestamp}@example.com"

## Standalone mode: Can invite second member without limit
post "/api/organizations/#{@org.extid}/invitations",
  { email: "member2_#{@timestamp}@example.com", role: 'member' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Second invitation created successfully
resp = JSON.parse(last_response.body)
@invite2_id = resp['record']['id']
resp['record']['email']
#=> "member2_#{@timestamp}@example.com"

## Organization has 2 pending invitations
reloaded_org = Onetime::Organization.load(@org.objid)
reloaded_org.pending_invitation_count
#=> 2

## With billing at limit (1 owner + 2 pending = 3/3): inviting fails with 422
@result1 = run_billing_test_invite(@org, @session, "member3_#{@timestamp}@example.com", @limited_plan)
@result1[:status]
#=> 422

## Error message indicates member limit reached
@result1[:error_message].to_s.include?('limit reached')
#=> true

## After accepting one invitation: still at limit (2 active + 1 pending = 3/3)
# Accept invitation within test case code (not loose between tests)
@invite1 = Onetime::OrganizationMembership.load(@invite1_id)
@member1 = Onetime::Customer.create!(email: "member1_#{@timestamp}@example.com")
@member1.verified = 'true'
@member1.save
@invite1.accept!(@member1)
@org = Onetime::Organization.load(@org.objid)
@result2 = run_billing_test_invite(@org, @session, "member3_#{@timestamp}@example.com", @limited_plan)
@result2[:status]
#=> 422

## Revoke invite2: removes from pending_invitations set
@invite2 = Onetime::OrganizationMembership.load(@invite2_id)
@invite2.revoke!
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitation_count
#=> 0

## After revoke: pending_invitations set is empty
@org.pending_invitations.to_a.empty?
#=> true

## Under limit (2/3), can invite new member
@result3 = run_billing_test_invite(@org, @session, "member4_#{@timestamp}@example.com", @limited_plan)
@result3[:status]
#=> 200

## Invitation created successfully when under limit
@invite3_id = @result3[:record_id]
@result3[:record_email]
#=> "member4_#{@timestamp}@example.com"

# Teardown
# invite1 was accepted (now active membership for @member1)
# invite2 was revoked (already destroyed)
# invite3 was created in billing block
[@invite1_id, @invite3_id].compact.each do |invite_id|
  invite = Onetime::OrganizationMembership.load(invite_id)
  invite&.destroy_with_index_cleanup!
end

@member1&.destroy!
@org&.destroy!
@owner&.destroy!
