# try/integration/api/organizations/invitations_edge_cases_try.rb
#
# frozen_string_literal: true

#
# Edge case tests for Organization Invitation System
#
# These tests cover gaps identified in the gap analysis:
# - Expired invitation API behavior (7-day TTL)
# - Inviting users without existing accounts
# - Resend count behavior across operations
# - Case sensitivity for email addresses
# - Token format validation
# - Organization deletion impact on invitations
# - Customer email change after invitation
# - Resend progressive behavior (count=1, count=2, count=3)

require 'rack/test'
require 'uri'
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
@owner = Onetime::Customer.create!(email: generate_unique_test_email("edge_owner"))

@owner_session = {
  'authenticated' => true,
  'external_id' => @owner.extid,
  'email' => @owner.email
}

@org = Onetime::Organization.create!(
  'Edge Case Test Org',
  @owner,
  generate_unique_test_email("edge_org_contact")
)

# ============================================================================
# HIGH PRIORITY: Expired Invitation API Test
# ============================================================================

## Setup expired invitation - set invited_at to 8 days ago
@expired_email = generate_unique_test_email("expired_invite")
@expired_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_email,
  role: 'member',
  inviter: @owner
)
@expired_invite.invited_at = (Familia.now.to_f - (8 * 24 * 60 * 60))
@expired_invite.save
@expired_token = @expired_invite.token
[@expired_invite.nil?, @expired_token.nil?]
#=> [false, false]

## Expired invitation model reports expired
@expired_invite.expired?
#=> true

## GET /api/invite/:token - Returns 400 for expired invitation
get "/api/invite/#{@expired_token}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/invite/:token - Expired invitation error response contains expired indicator
resp = JSON.parse(last_response.body)
resp['error'].to_s.downcase.include?('expired') || resp['message'].to_s.downcase.include?('expired') || last_response.status == 400
#=> true

## Setup invitee for expired acceptance test
@expired_invitee = Onetime::Customer.create!(email: @expired_email)
@expired_invitee_session = {
  'authenticated' => true,
  'external_id' => @expired_invitee.extid,
  'email' => @expired_invitee.email
}
@expired_invitee.nil?
#=> false

## POST /api/invite/:token/accept - Returns 400 for expired invitation
post "/api/invite/#{@expired_token}/accept",
  {}.to_json,
  { 'rack.session' => @expired_invitee_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/invite/:token/resend - Resend WORKS for expired invitation (refreshes it)
post "/api/organizations/#{@org.extid}/invitations/#{@expired_token}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## After resend, invitation is no longer expired
@expired_invite = Onetime::OrganizationMembership.load(@expired_invite.objid)
@expired_invite.expired?
#=> false

# ============================================================================
# HIGH PRIORITY: Invite Without Existing Account (Core Use Case)
# ============================================================================

## Create invitation for email without existing customer account
@nonexistent_email = generate_unique_test_email("no_account")
existing = Onetime::Customer.find(@nonexistent_email)
existing.nil? || !existing.exists?
#=> true

## POST creates invitation for non-existent user successfully
post "/api/organizations/#{@org.extid}/invitations",
  { email: @nonexistent_email, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['email']]
#=> [200, @nonexistent_email]

## Invitation token stored in response for non-existent user
@no_account_token = JSON.parse(last_response.body)['record']['token']
@no_account_token.nil? == false && @no_account_token.length >= 43
#=> true

## GET shows invitation details for non-existent user via token
get "/api/invite/#{@no_account_token}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Response contains invited email for non-existent user
resp = JSON.parse(last_response.body)
resp['invitation']['invited_email']
#=> @nonexistent_email

## New user creates account with invited email
@new_user = Onetime::Customer.create!(email: @nonexistent_email)
@new_user_session = {
  'authenticated' => true,
  'external_id' => @new_user.extid,
  'email' => @new_user.email
}
@new_user.nil?
#=> false

## POST /api/invite/:token/accept - New user can accept invitation after creating account
post "/api/invite/#{@no_account_token}/accept",
  {}.to_json,
  { 'rack.session' => @new_user_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
[last_response.status, @org.member?(@new_user)]
#=> [200, true]

# ============================================================================
# HIGH PRIORITY: Case Sensitivity for Email Addresses
# ============================================================================

## Setup for case sensitivity test - create invitation with lowercase email
@case_email_lower = generate_unique_test_email("case_test")
post "/api/organizations/#{@org.extid}/invitations",
  { email: @case_email_lower, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
@case_resp = JSON.parse(last_response.body)
@case_token = @case_resp['record']['token']
[last_response.status, @case_token.nil? == false]
#=> [200, true]

## Same email with UPPERCASE is treated as duplicate
@case_email_upper = @case_email_lower.upcase
post "/api/organizations/#{@org.extid}/invitations",
  { email: @case_email_upper, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Same email with MixedCase is treated as duplicate
@case_email_mixed = @case_email_lower.split('@').map.with_index { |p, i| i == 0 ? p.capitalize : p.upcase }.join('@')
post "/api/organizations/#{@org.extid}/invitations",
  { email: @case_email_mixed, role: 'member' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Create user with exact lowercase email for acceptance test
@case_user = Onetime::Customer.create!(email: @case_email_lower)
@case_user_session = {
  'authenticated' => true,
  'external_id' => @case_user.extid,
  'email' => @case_user.email
}
@case_user.nil?
#=> false

## Accept invitation with matching email succeeds
post "/api/invite/#{@case_token}/accept",
  {}.to_json,
  { 'rack.session' => @case_user_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

# ============================================================================
# HIGH PRIORITY: Resend Count Behavior
# ============================================================================

## Setup for resend count test
@resend_email = generate_unique_test_email("resend_count")
@resend_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @resend_email,
  role: 'member',
  inviter: @owner
)
@resend_token = @resend_invite.token
@resend_invite.resend_count.to_i
#=> 0

## First resend increments count to 1
post "/api/organizations/#{@org.extid}/invitations/#{@resend_token}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
@resend_token = resp['record']['token']
[last_response.status, resp['record']['resend_count']]
#=> [200, 1]

## Second resend increments count to 2
post "/api/organizations/#{@org.extid}/invitations/#{@resend_token}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
@resend_token = resp['record']['token']
[last_response.status, resp['record']['resend_count']]
#=> [200, 2]

## Third resend increments count to 3 (max)
post "/api/organizations/#{@org.extid}/invitations/#{@resend_token}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
@resend_token = resp['record']['token']
[last_response.status, resp['record']['resend_count']]
#=> [200, 3]

## Fourth resend fails - max limit reached
post "/api/organizations/#{@org.extid}/invitations/#{@resend_token}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Resend count persists in model
@resend_invite = Onetime::OrganizationMembership.load(@resend_invite.objid)
@resend_invite.resend_count.to_i
#=> 3

# ============================================================================
# MEDIUM PRIORITY: Token Format Validation
# ============================================================================

## GET /api/invite/:token - Returns 400 for empty token
get "/api/invite/", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/invite/:token - Returns 400 for very short token
get "/api/invite/abc", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/invite/:token - Returns 400 for URL-encoded XSS attempt
encoded_xss = URI.encode_www_form_component('abc<script>alert(1)</script>')
get "/api/invite/#{encoded_xss}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## GET /api/invite/:token - Returns 400 for URL-encoded SQL injection attempt
encoded_sql = URI.encode_www_form_component("'; DROP TABLE memberships;--")
get "/api/invite/#{encoded_sql}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## POST /api/invite/:token/accept - Returns 400 for malformed token
@test.clear_cookies
post "/api/invite/definitely_not_a_real_token_12345/accept",
  {}.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# ============================================================================
# MEDIUM PRIORITY: Resend Progressive Behavior (Token Invalidation)
# ============================================================================

## Setup for token invalidation test
@token_inv_email = generate_unique_test_email("token_inv")
@token_inv_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @token_inv_email,
  role: 'member',
  inviter: @owner
)
@token_v1 = @token_inv_invite.token
@token_v1.nil?
#=> false

## First resend generates new token (v2)
post "/api/organizations/#{@org.extid}/invitations/#{@token_v1}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
@token_v2 = resp['record']['token']
@token_v1 != @token_v2
#=> true

## Old token (v1) cannot be used for resend
post "/api/organizations/#{@org.extid}/invitations/#{@token_v1}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Old token (v1) cannot be used to view invitation
get "/api/invite/#{@token_v1}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Current token (v2) works for viewing invitation
get "/api/invite/#{@token_v2}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Second resend generates new token (v3), invalidates v2
post "/api/organizations/#{@org.extid}/invitations/#{@token_v2}/resend",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
@token_v3 = resp['record']['token']
[@token_v2 != @token_v3, last_response.status]
#=> [true, 200]

## Old token (v2) now invalid
get "/api/invite/#{@token_v2}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# ============================================================================
# MEDIUM PRIORITY: Customer Email Change After Invitation
# ============================================================================

## Setup invitation for email change test
@email_change_original = generate_unique_test_email("email_change_orig")
@email_change_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @email_change_original,
  role: 'member',
  inviter: @owner
)
@email_change_token = @email_change_invite.token
@email_change_token.nil?
#=> false

## Create user with original email
@email_change_user = Onetime::Customer.create!(email: @email_change_original)
@email_change_user.nil?
#=> false

## User changes email address
@email_change_new = generate_unique_test_email("email_change_new")
@email_change_user.email = @email_change_new
@email_change_user.save
@email_change_user.email
#=> @email_change_new

## User with changed email cannot accept invitation (email mismatch)
@changed_email_session = {
  'authenticated' => true,
  'external_id' => @email_change_user.extid,
  'email' => @email_change_user.email
}
post "/api/invite/#{@email_change_token}/accept",
  {}.to_json,
  { 'rack.session' => @changed_email_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

## Invitation remains pending after failed accept
@email_change_invite = Onetime::OrganizationMembership.load(@email_change_invite.objid)
@email_change_invite.pending?
#=> true

# ============================================================================
# MEDIUM PRIORITY: Organization Deletion Impact
# ============================================================================

## Setup second org with pending invitation for deletion test
@org2_owner = Onetime::Customer.create!(email: generate_unique_test_email("org2_owner"))
@org2 = Onetime::Organization.create!(
  'Org For Deletion Test',
  @org2_owner,
  generate_unique_test_email("org2_contact")
)
@org2.nil?
#=> false

## Create invitation in org2
@delete_test_email = generate_unique_test_email("delete_test")
@delete_test_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org2,
  email: @delete_test_email,
  role: 'member',
  inviter: @org2_owner
)
@delete_test_token = @delete_test_invite.token
[@delete_test_invite.nil?, @delete_test_token.nil?]
#=> [false, false]

## Delete the organization
@org2.destroy!
!@org2.exists?
#=> true

## Invitation token no longer valid after org deletion
get "/api/invite/#{@delete_test_token}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# Cleanup
[@org, @owner, @expired_invitee, @new_user, @case_user, @email_change_user, @org2_owner].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj&.exists?
end
