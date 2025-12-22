# try/integration/api/organizations/invitations_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for Organization Admin Invitation API endpoints:
# - POST /api/organizations/:extid/invitations (create invitation)
# - GET /api/organizations/:extid/invitations (list pending invitations)
# - POST /api/organizations/:extid/invitations/:token/resend (resend invitation)
# - DELETE /api/organizations/:extid/invitations/:token (revoke invitation)

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

# Setup test data
@owner = Onetime::Customer.create!(email: generate_unique_test_email("invitations_owner"))
@admin = Onetime::Customer.create!(email: generate_unique_test_email("invitations_admin"))
@member = Onetime::Customer.create!(email: generate_unique_test_email("invitations_member"))
@outsider = Onetime::Customer.create!(email: generate_unique_test_email("invitations_outsider"))

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

@outsider_session = {
  'authenticated' => true,
  'external_id' => @outsider.extid,
  'email' => @outsider.email
}

# Create an organization with admin and member
@org = Onetime::Organization.create!(
  'Test Org for Invitations',
  @owner,
  generate_unique_test_email("org_contact")
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

## POST /api/organizations/:extid/invitations - Owner can create invitation
@invite_email1 = generate_unique_test_email("invite1")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email1, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['email'], resp['record']['role']]
#=> [200, @invite_email1, 'member']

## POST /api/organizations/:extid/invitations - Created invitation has correct fields
resp = JSON.parse(last_response.body)
record = resp['record']
[
  record.key?('id'),
  record.key?('organization_id'),
  record.key?('email'),
  record.key?('role'),
  record.key?('status'),
  record.key?('invited_by'),
  record.key?('invited_at'),
  record.key?('expires_at')
]
#=> [true, true, true, true, true, true, true, true]

## POST /api/organizations/:extid/invitations - Created invitation has pending status
resp = JSON.parse(last_response.body)
resp['record']['status']
#=> 'pending'

## POST /api/organizations/:extid/invitations - Admin can create invitation
@invite_email2 = generate_unique_test_email("invite2")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email2, role: 'admin' }.to_json,
  { 'rack.session' => @admin_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['email'], resp['record']['role']]
#=> [200, @invite_email2, 'admin']

## POST /api/organizations/:extid/invitations - Member cannot create invitation
@invite_email3 = generate_unique_test_email("invite3")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email3, role: 'member' }.to_json,
  { 'rack.session' => @member_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Outsider cannot create invitation
@invite_email4 = generate_unique_test_email("invite4")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email4, role: 'member' }.to_json,
  { 'rack.session' => @outsider_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Cannot create without authentication
@test.clear_cookies
@invite_email5 = generate_unique_test_email("invite5")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email5, role: 'member' }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Returns 400 without email
post "/api/organizations/#{@org.extid}/invitations",
  { role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Returns 400 with invalid email
post "/api/organizations/#{@org.extid}/invitations",
  { email: 'invalid-email', role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Returns 400 with invalid role
@invite_email6 = generate_unique_test_email("invite6")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email6, role: 'invalid_role' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Returns 400 when inviting existing member
post "/api/organizations/#{@org.extid}/invitations",
  { email: @admin.email, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations - Returns 400 when duplicate pending invitation exists
post "/api/organizations/#{@org.extid}/invitations",
  { email: @invite_email1, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/organizations/:extid/invitations - Owner can list pending invitations
get "/api/organizations/#{@org.extid}/invitations",
  {},
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp.key?('records'), resp['records'].size >= 2]
#=> [200, true, true]

## GET /api/organizations/:extid/invitations - Listed invitations have correct structure
resp = JSON.parse(last_response.body)
first_invite = resp['records'].first
[
  first_invite.key?('email'),
  first_invite.key?('role'),
  first_invite.key?('status')
]
#=> [true, true, true]

## GET /api/organizations/:extid/invitations - Only returns pending invitations
resp = JSON.parse(last_response.body)
resp['records'].all? { |inv| inv['status'] == 'pending' }
#=> true

## GET /api/organizations/:extid/invitations - Admin can list invitations
get "/api/organizations/#{@org.extid}/invitations",
  {},
  { 'rack.session' => @admin_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## GET /api/organizations/:extid/invitations - Member cannot list invitations
get "/api/organizations/#{@org.extid}/invitations",
  {},
  { 'rack.session' => @member_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Get token for resend/revoke tests
@invitation_to_resend = Onetime::OrganizationMembership.find_by_org_email(@org.objid, @invite_email1)
@token_to_resend = @invitation_to_resend.token
@original_invited_at = @invitation_to_resend.invited_at

## POST /api/organizations/:extid/invitations/:token/resend - Owner can resend invitation
sleep 0.01 # Ensure timestamp difference
post "/api/organizations/#{@org.extid}/invitations/#{@token_to_resend}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['resend_count']]
#=> [200, 1]

## POST /api/organizations/:extid/invitations/:token/resend - Resend generates new token
resp = JSON.parse(last_response.body)
@new_token = resp['record']['token']
@new_token != @token_to_resend
#=> true

## POST /api/organizations/:extid/invitations/:token/resend - Resend updates timestamp
@invitation_to_resend = Onetime::OrganizationMembership.load(@invitation_to_resend.objid)
@invitation_to_resend.invited_at > @original_invited_at
#=> true

## POST /api/organizations/:extid/invitations/:token/resend - Old token no longer works
post "/api/organizations/#{@org.extid}/invitations/#{@token_to_resend}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations/:token/resend - Admin can resend invitation
post "/api/organizations/#{@org.extid}/invitations/#{@new_token}/resend",
  {}.to_json,
  { 'rack.session' => @admin_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['resend_count']]
#=> [200, 2]

## POST /api/organizations/:extid/invitations/:token/resend - Member cannot resend invitation
@invitation_to_resend = Onetime::OrganizationMembership.load(@invitation_to_resend.objid)
@current_token = @invitation_to_resend.token
post "/api/organizations/#{@org.extid}/invitations/#{@current_token}/resend",
  {}.to_json,
  { 'rack.session' => @member_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/organizations/:extid/invitations/:token/resend - Returns 400 for invalid token
post "/api/organizations/#{@org.extid}/invitations/invalid_token/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Create invitation to test resend limit
@invite_email_limit = generate_unique_test_email("invite_limit")
@invitation_limit = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invite_email_limit,
  role: 'member',
  inviter: @owner
)
@invitation_limit.resend_count = 3 # MAX_RESENDS
@invitation_limit.save
@token_limit = @invitation_limit.token

## POST /api/organizations/:extid/invitations/:token/resend - Returns 400 when resend limit reached
post "/api/organizations/#{@org.extid}/invitations/#{@token_limit}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Get token for revoke test
@invitation_to_revoke = Onetime::OrganizationMembership.find_by_org_email(@org.objid, @invite_email2)
@token_to_revoke = @invitation_to_revoke.token

## DELETE /api/organizations/:extid/invitations/:token - Owner can revoke invitation
delete "/api/organizations/#{@org.extid}/invitations/#{@token_to_revoke}",
  {},
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['revoked']]
#=> [200, true]

## DELETE /api/organizations/:extid/invitations/:token - Revoked invitation status updated
@invitation_to_revoke = Onetime::OrganizationMembership.load(@invitation_to_revoke.objid)
@invitation_to_revoke.status
#=> 'revoked'

## DELETE /api/organizations/:extid/invitations/:token - Cannot revoke already revoked invitation
delete "/api/organizations/#{@org.extid}/invitations/#{@token_to_revoke}",
  {},
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Create invitation for admin revoke test
@invite_email_admin_revoke = generate_unique_test_email("invite_admin_revoke")
@invitation_admin_revoke = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invite_email_admin_revoke,
  role: 'member',
  inviter: @owner
)
@token_admin_revoke = @invitation_admin_revoke.token

## DELETE /api/organizations/:extid/invitations/:token - Admin can revoke invitation
delete "/api/organizations/#{@org.extid}/invitations/#{@token_admin_revoke}",
  {},
  { 'rack.session' => @admin_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

# Create invitation for member revoke test
@invite_email_member_revoke = generate_unique_test_email("invite_member_revoke")
@invitation_member_revoke = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invite_email_member_revoke,
  role: 'member',
  inviter: @owner
)
@token_member_revoke = @invitation_member_revoke.token

## DELETE /api/organizations/:extid/invitations/:token - Member cannot revoke invitation
delete "/api/organizations/#{@org.extid}/invitations/#{@token_member_revoke}",
  {},
  { 'rack.session' => @member_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## DELETE /api/organizations/:extid/invitations/:token - Returns 400 for invalid token
delete "/api/organizations/#{@org.extid}/invitations/invalid_token",
  {},
  { 'rack.session' => @owner_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Cleanup
@org.destroy!
@owner.destroy!
@admin.destroy!
@member.destroy!
@outsider.destroy!
