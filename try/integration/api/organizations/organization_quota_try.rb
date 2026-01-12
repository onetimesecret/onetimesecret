# try/integration/api/organizations/organization_quota_try.rb
#
# frozen_string_literal: true

#
# Integration test for Organization quota entitlement checks
# Verifies that CreateOrganization enforces organization limits

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

# Setup: Create customer with default workspace
@timestamp = Familia.now.to_i
@cust = Onetime::Customer.create!(email: "quota_test_#{@timestamp}@example.com")
@cust.verified = 'true'
@cust.save

# Create default organization (first one is free)
@default_org = Onetime::Organization.create!("Default Workspace", @cust, @cust.email)
@default_org.is_default = true
@default_org.save

@session = { 'authenticated' => true, 'external_id' => @cust.extid, 'email' => @cust.email }

## Standalone mode: Customer can create organizations without limit (no billing)
post '/api/organizations',
  { display_name: 'Second Org', contact_email: "second_#{@timestamp}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Second organization created successfully
resp = JSON.parse(last_response.body)
@second_org_id = resp['record']['id']
resp['record']['display_name']
#=> 'Second Org'

## Can create a third organization in standalone mode
post '/api/organizations',
  { display_name: 'Third Org', contact_email: "third_#{@timestamp}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Third organization created successfully
resp = JSON.parse(last_response.body)
@third_org_id = resp['record']['id']
resp['record']['display_name']
#=> 'Third Org'

## Customer now has 3 organizations (check via API)
get '/api/organizations',
  {},
  { 'rack.session' => @session }
resp = JSON.parse(last_response.body)
resp['records'].size
#=> 3

## With billing enabled and limit=2, creating 4th org fails (already have 3)
# Execute billing-enabled test and capture results
@billing_test_status = nil
@billing_test_error_message = nil
@billing_test_error_type = nil
BillingTestHelpers.with_billing_enabled(plans: [
  {
    plan_id: 'limited_plan',
    name: 'Limited Plan',
    tier: 'free',
    interval: 'month',
    region: 'us',
    entitlements: ['create_secrets'],
    limits: { 'organizations.max' => '2' }
  }
]) do
  @default_org.planid = 'limited_plan'
  @default_org.save

  post '/api/organizations',
    { display_name: 'Fourth Org (Should Fail)', contact_email: "fourth_#{@timestamp}@example.com" }.to_json,
    { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }

  @billing_test_status = last_response.status
  resp = JSON.parse(last_response.body)
  # API returns flat structure: {"error": "ErrorType", "message": "..."}
  @billing_test_error_type = resp['error']
  @billing_test_error_message = resp['message']
end
@billing_test_status
#=> 422

## Error response indicates quota limit reached
@billing_test_error_message.to_s.include?('limit reached')
#=> true

## Error type signals upgrade required (UX: show upgrade CTA)
@billing_test_error_type
#=> 'upgrade_required'

# Teardown
begin
  if @second_org_id
    @second_org = Onetime::Organization.load(@second_org_id)
    @second_org&.destroy!
  end

  if @third_org_id
    @third_org = Onetime::Organization.load(@third_org_id)
    @third_org&.destroy!
  end

  @default_org&.destroy!
  @cust&.destroy!
rescue StandardError => e
  warn "[Teardown] Cleanup error (ignorable): #{e.message}"
end
