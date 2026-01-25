# try/integration/api/domains/list_domains_isolation_try.rb
#
# frozen_string_literal: true

#
# Integration tests for cross-organization domain isolation.
#
# Bug: When a user has membership in multiple organizations, listing domains
# should ONLY return domains for the specifically requested organization
# (via org_id parameter), NOT domains from other organizations they have access to.
#
# Test scenarios:
# 1. Basic isolation: User with 2 orgs, request org B domains -> only org B's domains
# 2. URL param precedence: Session has org A active, request specifies org B -> org B's domains
# 3. Non-member access denied: Request domains for org user is NOT a member of -> 403 or empty
# 4. Empty org: Request domains for org with no domains -> empty list, not other org's domains
# 5. Regression test: User's active org has domains, views different org with no domains -> empty list

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

# Setup test data with unique identifiers
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Create primary test user who will be member of multiple organizations
@user = Onetime::Customer.create!(email: "isolation_user_#{@ts}_#{@entropy}@test.com")
@user_session = {
  'authenticated' => true,
  'external_id' => @user.extid,
  'email' => @user.email
}

# Create second user who owns a separate organization (for non-member tests)
@other_user = Onetime::Customer.create!(email: "isolation_other_#{@ts}_#{@entropy}@test.com")
@other_user_session = {
  'authenticated' => true,
  'external_id' => @other_user.extid,
  'email' => @other_user.email
}

# Create Organization A (owned by @user, has domains)
@org_a = Onetime::Organization.create!("Isolation Org A #{@ts}", @user, "org_a_#{@ts}@test.com")

# Create Organization B (owned by @user, starts empty, will get domains)
@org_b = Onetime::Organization.create!("Isolation Org B #{@ts}", @user, "org_b_#{@ts}@test.com")

# Create Organization C (owned by @other_user, @user is NOT a member)
@org_c = Onetime::Organization.create!("Isolation Org C #{@ts}", @other_user, "org_c_#{@ts}@test.com")

# Create domains for Org A
@domain_a1 = Onetime::CustomDomain.create!("secrets-a1-#{@ts}.example.com", @org_a.objid)
@domain_a2 = Onetime::CustomDomain.create!("api-a2-#{@ts}.example.com", @org_a.objid)

# Create domains for Org B
@domain_b1 = Onetime::CustomDomain.create!("secrets-b1-#{@ts}.example.com", @org_b.objid)

# Create domain for Org C (user should never see this)
@domain_c1 = Onetime::CustomDomain.create!("secrets-c1-#{@ts}.example.com", @org_c.objid)

## Setup verification - Org A has 2 domains, Org B has 1 domain
[
  @org_a.domain_count,
  @org_b.domain_count,
  @org_a.member?(@user),
  @org_b.member?(@user),
  @org_c.member?(@user)
]
#=> [2, 1, true, true, false]

## TEST 1: Basic isolation - Request Org B domains returns ONLY Org B domains
# User has membership in both Org A and Org B. Request Org B domains.
# Expected: Only Org B's domain (secrets-b1), NOT Org A's domains.
get '/api/domains',
  { 'org_id' => @org_b.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
domains_returned = resp['records'].map { |d| d['display_domain'] }
[
  last_response.status,
  domains_returned.size,
  domains_returned.include?("secrets-b1-#{@ts}.example.com"),
  domains_returned.include?("secrets-a1-#{@ts}.example.com"),
  domains_returned.include?("api-a2-#{@ts}.example.com")
]
#=> [200, 1, true, false, false]

## TEST 2: URL param precedence - org_id param overrides session's active org
# Session has Org A as active, but request explicitly specifies Org B.
# Expected: Returns Org B's domains, respecting the explicit parameter.
get '/api/domains',
  { 'org_id' => @org_b.objid },  # Using objid instead of extid
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[
  last_response.status,
  resp['records'].size,
  resp['organization']['extid'] == @org_b.extid
]
#=> [200, 1, true]

## TEST 3: Request Org A domains explicitly returns ONLY Org A domains
# Confirms isolation works in both directions.
get '/api/domains',
  { 'org_id' => @org_a.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_b.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
domains_returned = resp['records'].map { |d| d['display_domain'] }
[
  last_response.status,
  domains_returned.size,
  domains_returned.include?("secrets-a1-#{@ts}.example.com"),
  domains_returned.include?("api-a2-#{@ts}.example.com"),
  domains_returned.include?("secrets-b1-#{@ts}.example.com")
]
#=> [200, 2, true, true, false]

## TEST 4: Non-member access denied - Request domains for org user is NOT a member of
# User requests domains for Org C (owned by @other_user, user has no membership).
# Expected: Returns error (403 unauthorized or form error).
get '/api/domains',
  { 'org_id' => @org_c.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
# Should fail with 400 (form error for unauthorized access)
last_response.status >= 400
#=> true

## TEST 5: Non-member access - verify error message indicates access denied
resp = JSON.parse(last_response.body) rescue {}
[
  resp['message']&.include?('access denied') || resp['message']&.include?('not found'),
  resp['records'].nil?
]
#=> [true, true]

## TEST 6: Empty org - Create new org with no domains, request its domains
@org_empty = Onetime::Organization.create!("Isolation Empty Org #{@ts}", @user, "org_empty_#{@ts}@test.com")
get '/api/domains',
  { 'org_id' => @org_empty.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[
  last_response.status,
  resp['records'].size,
  resp['count'],
  resp['organization']['extid'] == @org_empty.extid
]
#=> [200, 0, 0, true]

## TEST 7: REGRESSION - User's active org has domains, views different org with no domains
# This is the exact bug scenario: user with domains in one org switches to view
# another org that has no domains. Should see empty list, NOT the first org's domains.
get '/api/domains',
  { 'org_id' => @org_empty.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
domains_returned = resp['records'].map { |d| d['display_domain'] }
[
  last_response.status,
  domains_returned.empty?,
  # Critically: none of Org A's domains should leak through
  domains_returned.none? { |d| d.include?("secrets-a1-#{@ts}") },
  domains_returned.none? { |d| d.include?("api-a2-#{@ts}") }
]
#=> [200, true, true, true]

## TEST 8: Response includes correct organization context
# Verify the response organization field matches the requested org, not session's active org.
get '/api/domains',
  { 'org_id' => @org_b.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[
  resp['organization']['extid'] == @org_b.extid,
  resp['organization']['display_name'] == "Isolation Org B #{@ts}"
]
#=> [true, true]

## TEST 9: Invalid org_id returns appropriate error
get '/api/domains',
  { 'org_id' => 'nonexistent_org_12345' },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status >= 400
#=> true

## TEST 10: Malformed org_id handled gracefully
get '/api/domains',
  { 'org_id' => '"><script>alert(1)</script>' },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org_a.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
# Should fail gracefully (either sanitized or rejected)
last_response.status >= 400
#=> true

## TEST 11: Other user can only see their own org's domains
get '/api/domains',
  { 'org_id' => @org_c.extid },
  {
    'rack.session' => @other_user_session.merge('organization_extid' => @org_c.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
domains_returned = resp['records'].map { |d| d['display_domain'] }
[
  last_response.status,
  domains_returned.size,
  domains_returned.include?("secrets-c1-#{@ts}.example.com"),
  # Confirm other orgs' domains not leaked
  domains_returned.none? { |d| d.include?("secrets-a1-#{@ts}") },
  domains_returned.none? { |d| d.include?("secrets-b1-#{@ts}") }
]
#=> [200, 1, true, true, true]

## TEST 12: Other user cannot access first user's orgs
get '/api/domains',
  { 'org_id' => @org_a.extid },
  {
    'rack.session' => @other_user_session.merge('organization_extid' => @org_c.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status >= 400
#=> true

# Teardown - Clean up all test data
@domain_a1.destroy!
@domain_a2.destroy!
@domain_b1.destroy!
@domain_c1.destroy!
@org_a.destroy!
@org_b.destroy!
@org_c.destroy!
@org_empty.destroy!
@user.destroy!
@other_user.destroy!
