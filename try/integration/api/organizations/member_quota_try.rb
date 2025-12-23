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

## Standalone mode: Can invite members without limit (no billing)
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

## Can invite second member in standalone mode
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

## Organization has 2 pending invitations (reload to get updated counts)
reloaded_org = Onetime::Organization.load(@org.objid)
reloaded_org.pending_invitation_count
#=> 2

# Setup billing with member limit
BillingTestHelpers.with_billing_enabled(plans: [
  {
    plan_id: 'limited_members',
    name: 'Limited Members Plan',
    tier: 'free',
    interval: 'month',
    region: 'us',
    entitlements: ['create_secrets'],
    limits: { 'members_per_team.max' => '3' }  # Limit: 3 total members (owner + 2 invites)
  }
]) do
  # Assign limited plan to organization
  @org.planid = 'limited_members'
  @org.save

  # Reload org to ensure entitlements are loaded
  @org = Onetime::Organization.load(@org.objid)

  ## With billing enabled: at limit (1 owner + 2 pending = 3/3)
  @org.member_count + @org.pending_invitation_count
  #=> 3

  ## Inviting 4th member should fail (quota reached)
  post "/api/organizations/#{@org.extid}/invitations",
    { email: "member3_#{@timestamp}@example.com", role: 'member' }.to_json,
    { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
  last_response.status
  #=> 422

  ## Error response indicates member limit reached
  resp = JSON.parse(last_response.body)
  resp['error']['message'].include?('Member limit reached')
  #=> true

  ## Error type is upgrade_required
  resp['error']['type']
  #=> 'upgrade_required'

  ## Error field is email
  resp['error']['field']
  #=> 'email'
end

# Accept one invitation to free up space
@invite1 = Onetime::OrganizationMembership.load(@invite1_id)
@member1 = Onetime::Customer.create!(email: "member1_#{@timestamp}@example.com")
@member1.verified = 'true'
@member1.save
@invite1.accept!(@member1)
@org = Onetime::Organization.load(@org.objid)

# Setup billing again with same limit
BillingTestHelpers.with_billing_enabled(plans: [
  {
    plan_id: 'limited_members',
    name: 'Limited Members Plan',
    tier: 'free',
    interval: 'month',
    region: 'us',
    entitlements: ['create_secrets'],
    limits: { 'members_per_team.max' => '3' }
  }
]) do
  @org.planid = 'limited_members'
  @org.save
  @org = Onetime::Organization.load(@org.objid)

  ## With one accepted member: 2 active + 1 pending = 3/3 (still at limit)
  @org.member_count + @org.pending_invitation_count
  #=> 3

  ## Still cannot invite (at limit)
  post "/api/organizations/#{@org.extid}/invitations",
    { email: "member3_#{@timestamp}@example.com", role: 'member' }.to_json,
    { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
  last_response.status
  #=> 422
end

# Delete pending invitation to free up space
@invite2 = Onetime::OrganizationMembership.load(@invite2_id)
@invite2.destroy!
@org = Onetime::Organization.load(@org.objid)

# Setup billing with same limit, but now under quota
BillingTestHelpers.with_billing_enabled(plans: [
  {
    plan_id: 'limited_members',
    name: 'Limited Members Plan',
    tier: 'free',
    interval: 'month',
    region: 'us',
    entitlements: ['create_secrets'],
    limits: { 'members_per_team.max' => '3' }
  }
]) do
  @org.planid = 'limited_members'
  @org.save
  @org = Onetime::Organization.load(@org.objid)

  ## Now under limit: 2 active + 0 pending = 2/3
  @org.member_count + @org.pending_invitation_count
  #=> 2

  ## Can invite when under limit
  post "/api/organizations/#{@org.extid}/invitations",
    { email: "member3_#{@timestamp}@example.com", role: 'member' }.to_json,
    { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
  last_response.status
  #=> 200

  ## Invitation created successfully
  resp = JSON.parse(last_response.body)
  @invite3_id = resp['record']['id']
  resp['record']['email']
  #=> "member3_#{@timestamp}@example.com"
end

# Teardown
begin
  [@invite1_id, @invite2_id, @invite3_id].compact.each do |invite_id|
    invite = Onetime::OrganizationMembership.load(invite_id)
    invite&.destroy!
  end

  @member1&.destroy!
  @org&.destroy!
  @owner&.destroy!
rescue StandardError => e
  warn "[Teardown] Cleanup error (ignorable): #{e.message}"
end
