# try/integration/api/invite/invite_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for public Invitation API endpoints:
# - GET /api/invite/:token (show invitation details)
# - POST /api/invite/:token/accept (accept invitation)
# - POST /api/invite/:token/decline (decline invitation)

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
@owner = Onetime::Customer.create!(email: generate_unique_test_email("invite_owner"))
@invitee_email = generate_unique_test_email("invite_recipient")
@invitee = Onetime::Customer.create!(email: @invitee_email)

@owner_session = {
  'authenticated' => true,
  'external_id' => @owner.extid,
  'email' => @owner.email
}

@invitee_session = {
  'authenticated' => true,
  'external_id' => @invitee.extid,
  'email' => @invitee.email
}

# Create an organization
@org = Onetime::Organization.create!(
  'Test Org for Invites',
  @owner,
  generate_unique_test_email("org_contact")
)

# Create a pending invitation
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee_email,
  role: 'member',
  inviter: @owner
)
@token = @invitation.token

## GET /api/invite/:token - Shows invitation details with valid token
get "/api/invite/#{@token}", {}, { 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp.key?('record'), resp['record']['organization_name']]
#=> [200, true, 'Test Org for Invites']

## GET /api/invite/:token - Returns expected invitation fields
resp = JSON.parse(last_response.body)
invite = resp['record']
[
  invite.key?('organization_name'),
  invite.key?('role'),
  invite.key?('email'),
  invite.key?('expires_at')
]
#=> [true, true, true, true]

## GET /api/invite/:token - Shows correct role
resp = JSON.parse(last_response.body)
resp['record']['role']
#=> 'member'

## GET /api/invite/:token - Returns 400 for invalid token
get "/api/invite/invalid_token_xyz", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/invite/:token - Returns 400 for missing token
get "/api/invite/", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/invite/:token/accept - Accepts invitation with authenticated user
post "/api/invite/#{@token}/accept",
  {}.to_json,
  { 'rack.session' => @invitee_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['organization']['id'], resp['role']]
#=> [200, @org.extid, 'member']

## POST /api/invite/:token/accept - User is now a member of organization
@org.member?(@invitee)
#=> true

## POST /api/invite/:token/accept - Invitation status updated to accepted
@invitation = Onetime::OrganizationMembership.load(@invitation.objid)
@invitation.status
#=> 'active'

## Setup for accept/decline tests - create second invitation
@invitee2_email = generate_unique_test_email("invite_recipient2")
@invitee2 = Onetime::Customer.create!(email: @invitee2_email)
@invitation2 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee2_email,
  role: 'admin',
  inviter: @owner
)
@token2 = @invitation2.token
[@invitation2.nil?, @token2.nil?]
#=> [false, false]

## POST /api/invite/:token/accept - Returns 400 without authentication
# Clear cookies to simulate unauthenticated request
@test.clear_cookies
post "/api/invite/#{@token2}/accept",
  {}.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Setup for email mismatch test - create wrong user
@wrong_user = Onetime::Customer.create!(email: generate_unique_test_email("wrong_user"))
@wrong_session = {
  'authenticated' => true,
  'external_id' => @wrong_user.extid,
  'email' => @wrong_user.email
}
@wrong_user.nil? == false
#=> true

## POST /api/invite/:token/accept - Returns 400 when email doesn't match
post "/api/invite/#{@token2}/accept",
  {}.to_json,
  { 'rack.session' => @wrong_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/invite/:token/accept - Email mismatch doesn't change membership status
@invitation2 = Onetime::OrganizationMembership.load(@invitation2.objid)
@invitation2.pending?
#=> true

## Setup for decline test - create third invitation
@invitee3_email = generate_unique_test_email("invite_recipient3")
@invitation3 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee3_email,
  role: 'member',
  inviter: @owner
)
@token3 = @invitation3.token
[@invitation3.nil?, @token3.nil?]
#=> [false, false]

## POST /api/invite/:token/decline - Declines invitation without authentication
# No authentication required for decline
@test.clear_cookies
post "/api/invite/#{@token3}/decline",
  {}.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['declined']]
#=> [200, true]

## POST /api/invite/:token/decline - Updates invitation status to declined
@invitation3 = Onetime::OrganizationMembership.load(@invitation3.objid)
@invitation3.status
#=> 'declined'

## Setup for already-accepted test - create and accept fourth invitation
@invitee4_email = generate_unique_test_email("invite_recipient4")
@invitee4 = Onetime::Customer.create!(email: @invitee4_email)
@invitee4_session = {
  'authenticated' => true,
  'external_id' => @invitee4.extid,
  'email' => @invitee4.email
}
@invitation4 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee4_email,
  role: 'member',
  inviter: @owner
)
@token4 = @invitation4.token
# Accept the invitation
@invitation4.accept!(@invitee4)
[@invitation4.nil?, @token4.nil?]
#=> [false, false]

## POST /api/invite/:token/accept - Returns 400 for already accepted invitation
post "/api/invite/#{@token4}/accept",
  {}.to_json,
  { 'rack.session' => @invitee4_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/invite/:token - Returns 400 for already accepted invitation
get "/api/invite/#{@token4}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Setup for already-declined test - create and decline fifth invitation
@invitee5_email = generate_unique_test_email("invite_recipient5")
@invitation5 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee5_email,
  role: 'member',
  inviter: @owner
)
@token5 = @invitation5.token
@invitation5.decline!
[@invitation5.nil?, @token5.nil?]
#=> [false, false]

## POST /api/invite/:token/decline - Returns 400 for already declined invitation
post "/api/invite/#{@token5}/decline",
  {}.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Cleanup
@org.destroy!
@owner.destroy!
@invitee.destroy!
@invitee2.destroy!
@invitee4.destroy!
@wrong_user.destroy!
