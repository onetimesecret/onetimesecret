# try/integration/api/domains/domain_recipients_try.rb
#
# frozen_string_literal: true

# Integration tests for per-domain incoming secrets recipient management.
#
# Tests the CRUD endpoints:
# - GET    /api/domains/:extid/recipients  -> GetDomainRecipients
# - PUT    /api/domains/:extid/recipients  -> UpdateDomainRecipients
# - DELETE /api/domains/:extid/recipients  -> RemoveDomainRecipients
#
# Key scenarios:
# 1. Get recipients for a domain with none configured
# 2. Update recipients with valid data
# 3. Get updated recipients (hashed, no emails exposed)
# 4. Remove all recipients
# 5. Validation: invalid email, max recipients, non-array input
# 6. Authorization: non-owner cannot access domain recipients

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def post(*args); @test.post(*args); end
def get(*args); @test.get(*args); end
def put(*args); @test.put(*args); end
def delete(*args); @test.delete(*args); end
def last_response; @test.last_response; end

# Setup: Create unique test data
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Create test user who owns a domain
@owner = Onetime::Customer.create!(email: "recipients_owner_#{@ts}_#{@entropy}@test.com")
@owner_session = {
  'authenticated' => true,
  'external_id' => @owner.extid,
  'email' => @owner.email
}

# Create organization and domain
@org = Onetime::Organization.create!("Recipients Test Org #{@ts}", @owner, "recipients_org_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("recipients-test-#{@ts}-#{@entropy}.example.com", @org.objid)

# Create non-owner user
@non_owner = Onetime::Customer.create!(email: "recipients_nonowner_#{@ts}_#{@entropy}@test.com")
@non_owner_session = {
  'authenticated' => true,
  'external_id' => @non_owner.extid,
  'email' => @non_owner.email
}
@non_owner_org = Onetime::Organization.create!("Non-Owner Org #{@ts}", @non_owner, "nonowner_org_#{@ts}@test.com")

## Setup verification - domain exists and owner is correct
[@domain.exists?, @domain.owner?(@owner), @domain.owner?(@non_owner)]
#=> [true, true, false]

## GET recipients for domain with none configured returns empty array
get "/api/domains/#{@domain.extid}/recipients",
  {},
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['recipients']]
#=> [200, []]

## GET recipients returns default config values
resp = JSON.parse(last_response.body)
[
  resp['record']['memo_max_length'],
  resp['record']['default_ttl'],
  resp['user_id'] == @owner.objid
]
#=> [50, 604800, true]

## PUT recipients with valid data succeeds
put "/api/domains/#{@domain.extid}/recipients",
  {
    'recipients' => [
      { 'email' => 'support@example.com', 'name' => 'Support Team' },
      { 'email' => 'admin@example.com', 'name' => 'Admin' }
    ]
  }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status
#=> 200

## PUT recipients returns hashed recipients (no emails)
resp = JSON.parse(last_response.body)
recipients = resp['record']['recipients']
[
  recipients.size,
  recipients.first.key?('hash'),
  recipients.first.key?('name'),
  recipients.first.key?('email')
]
#=> [2, true, true, false]

## GET recipients after update returns the hashed list
get "/api/domains/#{@domain.extid}/recipients",
  {},
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
recipients = resp['record']['recipients']
[last_response.status, recipients.size, recipients.map { |r| r['name'] }.sort]
#=> [200, 2, ["Admin", "Support Team"]]

## Recipient hashes are deterministic (same email produces same hash)
site_secret = OT.conf.dig('site', 'secret')
expected_hash = Digest::SHA256.hexdigest("support@example.com:#{site_secret}")
resp = JSON.parse(last_response.body)
support_recipient = resp['record']['recipients'].find { |r| r['name'] == 'Support Team' }
support_recipient['hash'] == expected_hash
#=> true

## PUT with empty array clears all recipients
put "/api/domains/#{@domain.extid}/recipients",
  { 'recipients' => [] }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['recipients']]
#=> [200, []]

## PUT recipients back for DELETE test
put "/api/domains/#{@domain.extid}/recipients",
  {
    'recipients' => [
      { 'email' => 'test@example.com', 'name' => 'Test User' }
    ]
  }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status
#=> 200

## DELETE recipients removes all recipients
delete "/api/domains/#{@domain.extid}/recipients",
  {},
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['recipients']]
#=> [200, []]

## VALIDATION: PUT with non-array recipients fails
put "/api/domains/#{@domain.extid}/recipients",
  { 'recipients' => 'not_an_array' }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('must be an array')]
#=> [422, true]

## VALIDATION: PUT with invalid email fails
put "/api/domains/#{@domain.extid}/recipients",
  {
    'recipients' => [
      { 'email' => 'not_a_valid_email', 'name' => 'Bad Email' }
    ]
  }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('Invalid email')]
#=> [422, true]

## VALIDATION: PUT with missing email fails
put "/api/domains/#{@domain.extid}/recipients",
  {
    'recipients' => [
      { 'name' => 'No Email User' }
    ]
  }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('requires an email')]
#=> [422, true]

## VALIDATION: PUT with too many recipients fails
max_recipients = Onetime::CustomDomain::IncomingSecretsConfig::MAX_RECIPIENTS
too_many = (1..(max_recipients + 1)).map { |i| { 'email' => "user#{i}@example.com", 'name' => "User #{i}" } }
put "/api/domains/#{@domain.extid}/recipients",
  { 'recipients' => too_many }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?("Maximum #{max_recipients}")]
#=> [422, true]

## AUTHORIZATION: Non-owner GET returns domain not found
get "/api/domains/#{@domain.extid}/recipients",
  {},
  {
    'rack.session' => @non_owner_session.merge('organization_extid' => @non_owner_org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('not found')]
#=> [422, true]

## AUTHORIZATION: Non-owner PUT returns domain not found
put "/api/domains/#{@domain.extid}/recipients",
  {
    'recipients' => [
      { 'email' => 'hacker@evil.com', 'name' => 'Hacker' }
    ]
  }.to_json,
  {
    'rack.session' => @non_owner_session.merge('organization_extid' => @non_owner_org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('not found')]
#=> [422, true]

## AUTHORIZATION: Non-owner DELETE returns domain not found
delete "/api/domains/#{@domain.extid}/recipients",
  {},
  {
    'rack.session' => @non_owner_session.merge('organization_extid' => @non_owner_org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('not found')]
#=> [422, true]

## EDGE CASE: GET with invalid extid format fails
get "/api/domains/INVALID_EXTID!/recipients",
  {},
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status >= 400
#=> true

## EDGE CASE: GET with nonexistent domain fails
get "/api/domains/cd000000000000/recipients",
  {},
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
[last_response.status, resp['message'].include?('not found')]
#=> [422, true]

## EDGE CASE: Recipient with whitespace-only name gets email username
put "/api/domains/#{@domain.extid}/recipients",
  {
    'recipients' => [
      { 'email' => 'noname@example.com', 'name' => '   ' }
    ]
  }.to_json,
  {
    'rack.session' => @owner_session.merge('organization_extid' => @org.extid),
    'CONTENT_TYPE' => 'application/json',
    'HTTP_ACCEPT' => 'application/json'
  }
resp = JSON.parse(last_response.body)
resp['record']['recipients'].first['name']
#=> "noname"

## Teardown: Clean up test data
begin
  @domain.destroy!
  @org.destroy!
  @owner.destroy!
  @non_owner_org.destroy!
  @non_owner.destroy!
  true
rescue => e
  "cleanup_error: #{e.class}"
end
#=> true
