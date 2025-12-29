# try/integration/api/organizations/members_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for Organization Member Management API endpoints:
# - GET /api/organizations/:extid/members (list members with roles)
# - PATCH /api/organizations/:extid/members/:member_extid/role (update member role)
# - DELETE /api/organizations/:extid/members/:member_extid (remove member)
#
# Role Hierarchy: owner > admin > member
#
# Authorization Rules:
# - List: Any member can list
# - Update Role: Only owner can change roles
# - Remove: Owner can remove anyone (except self), Admin can remove members only

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
def patch(*args); @test.patch(*args); end
def delete(*args); @test.delete(*args); end
def last_response; @test.last_response; end

# Setup test data
@owner = Onetime::Customer.create!(email: generate_unique_test_email("members_owner"))
@admin = Onetime::Customer.create!(email: generate_unique_test_email("members_admin"))
@member = Onetime::Customer.create!(email: generate_unique_test_email("members_member"))
@member2 = Onetime::Customer.create!(email: generate_unique_test_email("members_member2"))
@outsider = Onetime::Customer.create!(email: generate_unique_test_email("members_outsider"))

@owner_session = {
  'authenticated' => true,
  'external_id' => @owner.extid,
  'email' => @owner.email
}

@admin_session = {
  'authenticated' => true,
  'external_id' => @admin.extid,
  'email' => @admin.email
}

@member_session = {
  'authenticated' => true,
  'external_id' => @member.extid,
  'email' => @member.email
}

@member2_session = {
  'authenticated' => true,
  'external_id' => @member2.extid,
  'email' => @member2.email
}

@outsider_session = {
  'authenticated' => true,
  'external_id' => @outsider.extid,
  'email' => @outsider.email
}

# Create an organization with admin and members
@org = Onetime::Organization.create!(
  'Test Org for Members',
  @owner,
  generate_unique_test_email("org_members_contact")
)

# Add admin via invitation (then accept it)
@admin_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @admin.email,
  role: 'admin',
  inviter: @owner
)
@admin_invitation.accept!(@admin)

# Add member via invitation (then accept it)
@member_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @member.email,
  role: 'member',
  inviter: @owner
)
@member_invitation.accept!(@member)

# Add member2 via invitation (then accept it)
@member2_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @member2.email,
  role: 'member',
  inviter: @owner
)
@member2_invitation.accept!(@member2)


# =============================================================================
# GET /api/organizations/:extid/members - List Members
# =============================================================================

## GET /api/organizations/:extid/members - Owner can list all members
get "/api/organizations/#{@org.extid}/members",
  nil,
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['count']]
#=> [200, 4]

## GET /api/organizations/:extid/members - Response includes required fields
resp = JSON.parse(last_response.body)
records = resp['records']
first_record = records.first
[
  first_record.key?('id'),
  first_record.key?('email'),
  first_record.key?('role'),
  first_record.key?('joined_at'),
  first_record.key?('is_owner'),
  first_record.key?('is_current_user')
]
#=> [true, true, true, true, true, true]

## GET /api/organizations/:extid/members - Admin can list all members
get "/api/organizations/#{@org.extid}/members",
  nil,
  { 'rack.session' => @admin_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## GET /api/organizations/:extid/members - Member can list all members
get "/api/organizations/#{@org.extid}/members",
  nil,
  { 'rack.session' => @member_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## GET /api/organizations/:extid/members - Outsider cannot list members
get "/api/organizations/#{@org.extid}/members",
  nil,
  { 'rack.session' => @outsider_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/organizations/:extid/members - Requires authentication
@test.clear_cookies
get "/api/organizations/#{@org.extid}/members",
  nil,
  { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true


# =============================================================================
# PATCH /api/organizations/:extid/members/:member_extid/role - Update Role
# =============================================================================

## PATCH - Owner can promote member to admin
patch "/api/organizations/#{@org.extid}/members/#{@member.extid}/role",
  { role: 'admin' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['role']]
#=> [200, 'admin']

## PATCH - Owner can demote admin to member
patch "/api/organizations/#{@org.extid}/members/#{@member.extid}/role",
  { role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['role']]
#=> [200, 'member']

## PATCH - Admin cannot change roles
patch "/api/organizations/#{@org.extid}/members/#{@member.extid}/role",
  { role: 'admin' }.to_json,
  { 'rack.session' => @admin_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## PATCH - Member cannot change roles
patch "/api/organizations/#{@org.extid}/members/#{@member2.extid}/role",
  { role: 'admin' }.to_json,
  { 'rack.session' => @member_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## PATCH - Cannot set role to owner
patch "/api/organizations/#{@org.extid}/members/#{@member.extid}/role",
  { role: 'owner' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## PATCH - Cannot change owner's role
# First find the owner's membership to get their extid
patch "/api/organizations/#{@org.extid}/members/#{@owner.extid}/role",
  { role: 'admin' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## PATCH - Invalid role value returns error
patch "/api/organizations/#{@org.extid}/members/#{@member.extid}/role",
  { role: 'superadmin' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## PATCH - Non-existent member returns 404
patch "/api/organizations/#{@org.extid}/members/ur9999nonexistent/role",
  { role: 'admin' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 404


# =============================================================================
# DELETE /api/organizations/:extid/members/:member_extid - Remove Member
# =============================================================================

## DELETE - Owner can remove a member
delete "/api/organizations/#{@org.extid}/members/#{@member2.extid}",
  nil,
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['removed']]
#=> [200, true]

## DELETE - Verify member was actually removed
@org.member?(@member2)
#=> false

## DELETE - Admin cannot remove another admin
delete "/api/organizations/#{@org.extid}/members/#{@admin.extid}",
  nil,
  { 'rack.session' => @admin_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## DELETE - Member cannot remove anyone (try to remove admin)
delete "/api/organizations/#{@org.extid}/members/#{@admin.extid}",
  nil,
  { 'rack.session' => @member_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## DELETE - Cannot remove the owner
delete "/api/organizations/#{@org.extid}/members/#{@owner.extid}",
  nil,
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## DELETE - Owner can remove admin
delete "/api/organizations/#{@org.extid}/members/#{@admin.extid}",
  nil,
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['removed']]
#=> [200, true]

## DELETE - Outsider cannot remove members
delete "/api/organizations/#{@org.extid}/members/#{@member.extid}",
  nil,
  { 'rack.session' => @outsider_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## DELETE - Requires authentication
@test.clear_cookies
delete "/api/organizations/#{@org.extid}/members/#{@member.extid}",
  nil,
  { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true


# =============================================================================
# Cleanup
# =============================================================================

# Cleanup test data
@org.destroy! rescue nil
[@owner, @admin, @member, @member2, @outsider].each { |c| c.destroy! rescue nil }
