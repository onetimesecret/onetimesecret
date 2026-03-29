# try/integration/api/domains/list_domains_sso_fields_try.rb
#
# frozen_string_literal: true

#
# Integration tests for SSO status fields in domain list API response.
#
# Verifies that sso_configured and sso_enabled fields are included in
# the CustomDomain safe_dump output, enabling UI badges for SSO status.
#
# Test scenarios:
# 1. Domain without SSO config: sso_configured=false, sso_enabled=false
# 2. Domain with SSO config disabled: sso_configured=true, sso_enabled=false
# 3. Domain with SSO config enabled: sso_configured=true, sso_enabled=true

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

# Create test user and organization
@user = Onetime::Customer.create!(email: "sso_fields_user_#{@ts}_#{@entropy}@test.com")
@user_session = {
  'authenticated' => true,
  'external_id' => @user.extid,
  'email' => @user.email
}

@org = Onetime::Organization.create!("SSO Fields Test Org #{@ts}", @user, "sso_org_#{@ts}@test.com")

# Create three test domains
@domain_no_sso = Onetime::CustomDomain.create!("no-sso-#{@ts}.example.com", @org.objid)
@domain_sso_disabled = Onetime::CustomDomain.create!("sso-disabled-#{@ts}.example.com", @org.objid)
@domain_sso_enabled = Onetime::CustomDomain.create!("sso-enabled-#{@ts}.example.com", @org.objid)

## Setup verification - Organization has 3 domains
@org.domain_count
#=> 3

## TEST 1: Create SSO config for disabled domain (disabled by default)
@sso_config_disabled = Onetime::DomainSsoConfig.create!(
  domain_id: @domain_sso_disabled.identifier,
  provider_type: 'oidc',
  client_id: 'test-client-id',
  client_secret: 'test-client-secret',
  issuer: 'https://auth.example.com',
  display_name: 'Test SSO Disabled'
)
[@sso_config_disabled.enabled?, @sso_config_disabled.domain_id]
#=> [false, @domain_sso_disabled.identifier]

## TEST 2: Create SSO config for enabled domain
@sso_config_enabled = Onetime::DomainSsoConfig.create!(
  domain_id: @domain_sso_enabled.identifier,
  provider_type: 'entra_id',
  client_id: 'test-client-id-2',
  client_secret: 'test-client-secret-2',
  tenant_id: 'test-tenant-id',
  display_name: 'Test SSO Enabled',
  enabled: true
)
[@sso_config_enabled.enabled?, @sso_config_enabled.domain_id]
#=> [true, @domain_sso_enabled.identifier]

## TEST 3: Verify SSO config existence checks work
[
  Onetime::DomainSsoConfig.exists_for_domain?(@domain_no_sso.identifier),
  Onetime::DomainSsoConfig.exists_for_domain?(@domain_sso_disabled.identifier),
  Onetime::DomainSsoConfig.exists_for_domain?(@domain_sso_enabled.identifier)
]
#=> [false, true, true]

## TEST 4: Domain list API response includes SSO fields
get '/api/domains',
  { 'org_id' => @org.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status
#=> 200

## TEST 5: Parse response and find our test domains
@resp = JSON.parse(last_response.body)
@domains_by_name = @resp['records'].each_with_object({}) do |d, h|
  h[d['display_domain']] = d
end
@domains_by_name.keys.sort
#=> ["no-sso-#{@ts}.example.com", "sso-disabled-#{@ts}.example.com", "sso-enabled-#{@ts}.example.com"].sort

## TEST 6: Domain without SSO config has correct field values
@no_sso_record = @domains_by_name["no-sso-#{@ts}.example.com"]
[@no_sso_record['sso_configured'], @no_sso_record['sso_enabled']]
#=> [false, false]

## TEST 7: Domain with disabled SSO config has correct field values
@disabled_sso_record = @domains_by_name["sso-disabled-#{@ts}.example.com"]
[@disabled_sso_record['sso_configured'], @disabled_sso_record['sso_enabled']]
#=> [true, false]

## TEST 8: Domain with enabled SSO config has correct field values
@enabled_sso_record = @domains_by_name["sso-enabled-#{@ts}.example.com"]
[@enabled_sso_record['sso_configured'], @enabled_sso_record['sso_enabled']]
#=> [true, true]

## TEST 9: SSO fields are boolean types, not strings
[
  @no_sso_record['sso_configured'].class,
  @no_sso_record['sso_enabled'].class,
  @enabled_sso_record['sso_configured'].class,
  @enabled_sso_record['sso_enabled'].class
].all? { |klass| [TrueClass, FalseClass].include?(klass) }
#=> true

## TEST 10: Individual domain fetch also includes SSO fields
get "/api/domains/#{@domain_sso_enabled.extid}",
  {},
  {
    'rack.session' => @user_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
@single_resp = JSON.parse(last_response.body)
[@single_resp['record']['sso_configured'], @single_resp['record']['sso_enabled']]
#=> [true, true]

# Teardown - Clean up all test data
@sso_config_disabled.destroy! if @sso_config_disabled
@sso_config_enabled.destroy! if @sso_config_enabled
@domain_no_sso.destroy!
@domain_sso_disabled.destroy!
@domain_sso_enabled.destroy!
@org.destroy!
@user.destroy!
