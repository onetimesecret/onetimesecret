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

# Helper to enable domains feature at runtime level
def enable_runtime_domains!
  current_features = Onetime::Runtime.features
  Onetime::Runtime.features = Onetime::Runtime::Features.new(
    domains_enabled: true,
    global_banner: current_features.global_banner,
    fortunes: current_features.fortunes,
  )
end

# Helper to enable domain context override at middleware level
def enable_domain_context!
  Onetime::Middleware::DomainStrategy.class_eval { @domain_context_enabled = true }
end

# Helper to fully enable domains for branding tests
def enable_domains_for_branding_tests!
  # IMPORTANT: Must modify OT.conf directly because DomainStrategy.initialize
  # reads from OT.conf when middleware instances are created.
  # Simply calling initialize_from_config is not enough since it gets overwritten.
  OT.conf['features'] ||= {}
  OT.conf['features']['domains'] = {
    'enabled' => true,
    'default' => 'onetimesecret.com'
  }
  OT.conf['development'] ||= {}
  OT.conf['development']['domain_context_enabled'] = true

  enable_runtime_domains!
end

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
# After accept!, the UUID-keyed staged model is destroyed and replaced with a
# composite-keyed model. Use find_by_org_customer to look up the activated membership.
@activated_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invitee.objid)
@activated_membership.status
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

# ============================================================================
# BRANDING AND AUTH METHODS TESTS
# ============================================================================
# These tests verify that GET /api/invite/:token returns branding and
# auth_methods when accessed from a custom domain.

## Setup branding test infrastructure - create org, domain, and invitation
# First enable domains feature for these tests
enable_domains_for_branding_tests!
# Force Rack::Test to rebuild the app with the new config by creating a new test object
@test = Object.new
@test.extend Rack::Test::Methods
def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end
# Re-delegate to new test object
def get(*args); @test.get(*args); end
def post(*args); @test.post(*args); end
def last_response; @test.last_response; end
@branding_owner = Onetime::Customer.create!(email: generate_unique_test_email("branding_owner"))
@branding_invitee_email = generate_unique_test_email("branding_invitee")
@branding_org = Onetime::Organization.create!(
  'Branded Test Org',
  @branding_owner,
  generate_unique_test_email("branding_org_contact")
)
@custom_domain = Onetime::CustomDomain.create!("secrets.branding-test-#{SecureRandom.hex(4)}.example.com", @branding_org.objid)
@custom_domain.brand['name'] = 'ACME Corp'
@custom_domain.brand['primary_color'] = '#FF5500'
@custom_domain.save
@branding_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @branding_org,
  email: @branding_invitee_email,
  role: 'member',
  inviter: @branding_owner
)
@branding_token = @branding_invitation.token
[@branding_org.nil?, @custom_domain.nil?, @branding_invitation.nil?]
#=> [false, false, false]

## GET /api/invite/:token on canonical domain - branding is NOT present
# When accessing from canonical domain, branding should not be included
get "/api/invite/#{@branding_token}", {}, { 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record'].key?('branding')]
#=> [200, false]

## GET /api/invite/:token on canonical domain - auth_methods is NOT present
resp = JSON.parse(last_response.body)
resp['record'].key?('auth_methods')
#=> false

## Setup custom domain env and request - returns branding when custom domain configured
# The middleware sets these env vars when domain_strategy is :custom
@custom_domain_env = {
  'HTTP_ACCEPT' => 'application/json',
  'HTTP_O_DOMAIN_CONTEXT' => @custom_domain.display_domain,
  'onetime.domain_strategy' => :custom,
  'onetime.display_domain' => @custom_domain.display_domain,
}
get "/api/invite/#{@branding_token}", {}, @custom_domain_env
resp = JSON.parse(last_response.body)
[last_response.status, resp['record'].key?('branding')]
#=> [200, true]

## GET /api/invite/:token on custom domain - branding contains primary_color
resp = JSON.parse(last_response.body)
branding = resp['record']['branding']
branding.key?('primary_color')
#=> true

## GET /api/invite/:token on custom domain - primary_color value matches configured value
resp = JSON.parse(last_response.body)
branding = resp['record']['branding']
branding['primary_color']
#=> '#FF5500'

## GET /api/invite/:token on custom domain - branding contains display_name
resp = JSON.parse(last_response.body)
branding = resp['record']['branding']
branding.key?('display_name')
#=> true

## GET /api/invite/:token on custom domain - branding contains logo_url key
resp = JSON.parse(last_response.body)
branding = resp['record']['branding']
branding.key?('logo_url')
#=> true

## GET /api/invite/:token on custom domain - branding contains icon_url key
resp = JSON.parse(last_response.body)
branding = resp['record']['branding']
branding.key?('icon_url')
#=> true

## GET /api/invite/:token on custom domain - auth_methods present (password always enabled)
resp = JSON.parse(last_response.body)
resp['record'].key?('auth_methods')
#=> true

## GET /api/invite/:token on custom domain - auth_methods includes password type
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
auth_methods.any? { |m| m['type'] == 'password' }
#=> true

## GET /api/invite/:token on custom domain - password auth is enabled
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
password_method = auth_methods.find { |m| m['type'] == 'password' }
password_method['enabled']
#=> true

# ============================================================================
# SSO CONFIGURED TESTS
# ============================================================================

## Setup SSO config and verify it includes SSO in auth_methods
@sso_config = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @custom_domain.identifier,
  provider_type: 'entra_id',
  display_name: 'ACME Corp SSO',
  client_id: 'test-client-id-12345',
  client_secret: 'test-client-secret-67890',
  tenant_id: 'test-tenant-id-abcde',
  enabled: true
)
# Re-request with SSO now configured
get "/api/invite/#{@branding_token}", {}, @custom_domain_env
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
[@sso_config.nil?, auth_methods.any? { |m| m['type'] == 'sso' }]
#=> [false, true]

## GET /api/invite/:token with SSO configured - auth_methods has both password and sso
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
types = auth_methods.map { |m| m['type'] }.sort
types
#=> ['password', 'sso']

## GET /api/invite/:token with SSO configured - SSO includes provider_type
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('provider_type')
#=> true

## GET /api/invite/:token with SSO configured - SSO provider_type is entra_id
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method['provider_type']
#=> 'entra_id'

## GET /api/invite/:token with SSO configured - SSO includes display_name
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('display_name')
#=> true

## GET /api/invite/:token with SSO configured - SSO includes platform_route_name
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('platform_route_name')
#=> true

## GET /api/invite/:token with SSO configured - SSO enabled is true
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method['enabled']
#=> true

# ============================================================================
# SECURITY: NO CREDENTIAL EXPOSURE TESTS
# ============================================================================
# Critical: Verify that SSO credentials are NOT exposed in the API response

## Security: SSO response does NOT contain client_id
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('client_id')
#=> false

## Security: SSO response does NOT contain client_secret
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('client_secret')
#=> false

## Security: SSO response does NOT contain tenant_id
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('tenant_id')
#=> false

## Security: SSO response does NOT contain issuer
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
sso_method.key?('issuer')
#=> false

## Security: SSO fields are limited to safe public fields only
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
sso_method = auth_methods.find { |m| m['type'] == 'sso' }
allowed_fields = %w[type provider_type display_name enabled platform_route_name]
sso_method.keys.all? { |k| allowed_fields.include?(k) }
#=> true

# ============================================================================
# CLEANUP
# ============================================================================

# Reset domain config to test defaults to avoid affecting other tests
OT.conf['features'] ||= {}
OT.conf['features']['domains'] = { 'enabled' => false, 'default' => nil }
OT.conf['development'] ||= {}
OT.conf['development']['domain_context_enabled'] = false
Onetime::Runtime.features = Onetime::Runtime.features.with(domains_enabled: false)
Onetime::Middleware::DomainStrategy.reset! if Onetime::Middleware::DomainStrategy.respond_to?(:reset!)

# Clean up branding/SSO test resources
@sso_config.destroy! if @sso_config
@custom_domain.destroy! if @custom_domain
@branding_org.destroy! if @branding_org
@branding_owner.destroy! if @branding_owner

# Original cleanup
@org.destroy!
@owner.destroy!
@invitee.destroy!
@invitee2.destroy!
@invitee4.destroy!
@wrong_user.destroy!
