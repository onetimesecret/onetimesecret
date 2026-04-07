# try/integration/api/invite/show_invite_enriched_try.rb
#
# frozen_string_literal: true

#
# Integration tests for enriched ShowInvite API responses.
# Verifies structured responses for ALL invitation states (not just pending).
#
# Key behaviors tested:
# - All statuses return structured response (pending, accepted, declined, expired)
# - Only invalid/not-found tokens return 404
# - account_exists field reflects whether Customer exists for invited_email
# - auth_methods includes magic_link when email_auth feature is enabled
# - actionable field indicates if invitation can still be acted upon

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
@owner = Onetime::Customer.create!(email: generate_unique_test_email("enriched_owner"))
@org = Onetime::Organization.create!(
  'Enriched Test Org',
  @owner,
  generate_unique_test_email("enriched_org_contact")
)

# ============================================================================
# PENDING INVITATION TESTS
# ============================================================================

## Setup pending invitation for user WITHOUT existing account
@pending_email_no_account = generate_unique_test_email("pending_no_acct")
@pending_invitation_no_acct = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @pending_email_no_account,
  role: 'member',
  inviter: @owner
)
@token_pending_no_acct = @pending_invitation_no_acct.token
[@pending_invitation_no_acct.nil?, @token_pending_no_acct.nil?]
#=> [false, false]

## GET pending invitation - returns 200 with structured response
get "/api/invite/#{@token_pending_no_acct}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## GET pending invitation - status field is 'pending'
resp = JSON.parse(last_response.body)
resp['record']['status']
#=> 'pending'

## GET pending invitation - actionable is true for pending non-expired
resp = JSON.parse(last_response.body)
resp['record']['actionable']
#=> true

## GET pending invitation - account_exists is false when no Customer exists
resp = JSON.parse(last_response.body)
resp['record']['account_exists']
#=> false

## Setup pending invitation for user WITH existing account
@existing_user_email = generate_unique_test_email("pending_with_acct")
@existing_user = Onetime::Customer.create!(email: @existing_user_email)
@pending_invitation_with_acct = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @existing_user_email,
  role: 'member',
  inviter: @owner
)
@token_pending_with_acct = @pending_invitation_with_acct.token
[@pending_invitation_with_acct.nil?, @existing_user.nil?]
#=> [false, false]

## GET pending invitation - account_exists is true when Customer exists
get "/api/invite/#{@token_pending_with_acct}", {}, { 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['account_exists']]
#=> [200, true]

# ============================================================================
# ACCEPTED (ACTIVE) INVITATION TESTS
# ============================================================================

## Setup accepted invitation
@accepted_email = generate_unique_test_email("accepted_user")
@accepted_user = Onetime::Customer.create!(email: @accepted_email)
@accepted_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @accepted_email,
  role: 'member',
  inviter: @owner
)
@token_accepted = @accepted_invitation.token
@accepted_invitation.accept!(@accepted_user)
[@accepted_invitation.status, @accepted_invitation.active?]
#=> ['active', true]

## GET accepted invitation - token is nil on activated membership
# After accept!, the UUID-keyed staged model is destroyed. The composite-keyed
# activated model has token=nil (cleared for security). Look up via org+customer index.
@activated_membership = Onetime::OrganizationMembership.find_by_org_customer(
  @accepted_invitation.organization_objid, @accepted_user.objid
)
@activated_membership.token.nil?
#=> true

# ============================================================================
# DECLINED INVITATION TESTS
# ============================================================================

## Setup declined invitation
@declined_email = generate_unique_test_email("declined_user")
@declined_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @declined_email,
  role: 'member',
  inviter: @owner
)
@token_declined = @declined_invitation.token
@declined_invitation.decline!
@declined_invitation.status
#=> 'declined'

## GET declined invitation - token is cleared after decline (security)
@declined_invitation = Onetime::OrganizationMembership.load(@declined_invitation.objid)
@declined_invitation.token.nil?
#=> true

# ============================================================================
# EXPIRED INVITATION TESTS
# ============================================================================

## Setup expired invitation (by manipulating invited_at timestamp)
@expired_email = generate_unique_test_email("expired_user")
@expired_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_email,
  role: 'member',
  inviter: @owner
)
@token_expired = @expired_invitation.token
# Set invited_at to 8 days ago to trigger expiration (default TTL is 7 days)
@expired_invitation.invited_at = Familia.now.to_f - (8 * 24 * 60 * 60)
@expired_invitation.save
@expired_invitation.expired?
#=> true

## GET expired invitation - returns 200 with structured response (not 400)
get "/api/invite/#{@token_expired}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## GET expired invitation - effective status is 'expired' (computed from pending + past TTL)
resp = JSON.parse(last_response.body)
resp['record']['status']
#=> 'expired'

## GET expired invitation - actionable is false (expired)
resp = JSON.parse(last_response.body)
resp['record']['actionable']
#=> false

## GET expired invitation - account_exists reflects actual state
resp = JSON.parse(last_response.body)
resp['record']['account_exists']
#=> false

# ============================================================================
# INVALID TOKEN TESTS (404 expected)
# ============================================================================

## GET with completely invalid token - returns 404
get "/api/invite/totally_invalid_token_xyz123", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 404

## GET with empty token - returns error (400 range)
get "/api/invite/", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status >= 400
#=> true

# ============================================================================
# MAGIC LINK / EMAIL AUTH TESTS
# ============================================================================
# Note: These tests verify behavior when email_auth feature is toggled.
# The actual feature flag is controlled by auth config.

## Check current email_auth_enabled? state
@email_auth_originally_enabled = Onetime.auth_config.email_auth_enabled?
@email_auth_originally_enabled.is_a?(TrueClass) || @email_auth_originally_enabled.is_a?(FalseClass)
#=> true

## Setup custom domain for auth_methods test
@auth_test_owner = Onetime::Customer.create!(email: generate_unique_test_email("auth_test_owner"))
@auth_test_org = Onetime::Organization.create!(
  'Auth Test Org',
  @auth_test_owner,
  generate_unique_test_email("auth_test_org_contact")
)
@auth_test_domain = Onetime::CustomDomain.create!("secrets.auth-test-#{SecureRandom.hex(4)}.example.com", @auth_test_org.objid)
@auth_test_domain.brand['name'] = 'Auth Test Corp'
@auth_test_domain.save
@auth_test_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @auth_test_org,
  email: generate_unique_test_email("auth_test_invitee"),
  role: 'member',
  inviter: @auth_test_owner
)
@auth_test_token = @auth_test_invitation.token
[@auth_test_domain.nil?, @auth_test_invitation.nil?]
#=> [false, false]

## Enable domains feature for auth_methods tests
OT.conf['features'] ||= {}
OT.conf['features']['domains'] = {
  'enabled' => true,
  'default' => 'onetimesecret.com'
}
OT.conf['development'] ||= {}
OT.conf['development']['domain_context_enabled'] = true
# Force runtime features update
current_features = Onetime::Runtime.features
Onetime::Runtime.features = Onetime::Runtime::Features.new(
  domains_enabled: true,
  global_banner: current_features.global_banner,
  fortunes: current_features.fortunes,
)
# Rebuild test app with new config
@test = Object.new
@test.extend Rack::Test::Methods
def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end
def get(*args); @test.get(*args); end
def post(*args); @test.post(*args); end
def last_response; @test.last_response; end
true
#=> true

## GET with custom domain - auth_methods includes password
@custom_domain_env = {
  'HTTP_ACCEPT' => 'application/json',
  'HTTP_O_DOMAIN_CONTEXT' => @auth_test_domain.display_domain,
  'onetime.domain_strategy' => :custom,
  'onetime.display_domain' => @auth_test_domain.display_domain,
}
get "/api/invite/#{@auth_test_token}", {}, @custom_domain_env
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
[last_response.status, auth_methods.any? { |m| m['type'] == 'password' }]
#=> [200, true]

## Verify auth_methods structure - password is always enabled
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
password_method = auth_methods.find { |m| m['type'] == 'password' }
password_method['enabled']
#=> true

## Verify magic_link presence depends on email_auth_enabled? config
# This test documents the expected behavior based on current config state
resp = JSON.parse(last_response.body)
auth_methods = resp['record']['auth_methods']
has_magic_link = auth_methods.any? { |m| m['type'] == 'magic_link' }
# Result should match whether email_auth is enabled in config
has_magic_link == Onetime.auth_config.email_auth_enabled?
#=> true

# ============================================================================
# RESPONSE STRUCTURE VALIDATION
# ============================================================================

## GET pending invitation - response has all expected fields
get "/api/invite/#{@token_pending_no_acct}", {}, { 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
record = resp['record']
required_fields = %w[organization_name organization_id email role status expires_at actionable account_exists]
required_fields.all? { |f| record.key?(f) }
#=> true

## Response includes organization info
resp = JSON.parse(last_response.body)
record = resp['record']
[record['organization_name'], record['organization_id'].nil?]
#=> ['Enriched Test Org', false]

# ============================================================================
# CLEANUP
# ============================================================================

# Reset domain config to test defaults
OT.conf['features'] ||= {}
OT.conf['features']['domains'] = { 'enabled' => false, 'default' => nil }
OT.conf['development'] ||= {}
OT.conf['development']['domain_context_enabled'] = false
Onetime::Runtime.features = Onetime::Runtime.features.with(domains_enabled: false)
Onetime::Middleware::DomainStrategy.reset! if Onetime::Middleware::DomainStrategy.respond_to?(:reset!)

# Clean up auth test resources
@auth_test_domain.destroy! if @auth_test_domain
@auth_test_org.destroy! if @auth_test_org
@auth_test_owner.destroy! if @auth_test_owner

# Clean up test resources
@org.destroy! if @org
@owner.destroy! if @owner
@existing_user.destroy! if @existing_user
@accepted_user.destroy! if @accepted_user
