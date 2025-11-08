# try/integration/api/organizations/organizations_api_try.rb
#
# Integration tests for Organizations CRUD API endpoints:
# - POST /api/organizations (create organization)
# - GET /api/organizations (list user's organizations)
# - GET /api/organizations/:orgid (get organization details)
# - PUT /api/organizations/:orgid (update organization)
# - DELETE /api/organizations/:orgid (delete organization)

require 'rack/test'
require_relative '../../../support/test_helpers'

begin
  OT.boot! :test, false unless OT.ready?
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

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
@cust = Onetime::Customer.create!(email: "testuser#{Familia.now.to_i}@onetimesecret.com")
@session = { 'authenticated' => true, 'external_id' => @cust.extid, 'email' => @cust.email }

## Can create organization via API - check status first
post '/api/organizations',
  { display_name: 'API Test Org', description: 'Created via API', contact_email: "contact#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Can parse create organization response
resp = JSON.parse(last_response.body)
@orgid = resp['record']['orgid']
[resp['record']['display_name'], resp['record']['owner_id']]
#=> ['API Test Org', @cust.custid]

## Created organization response includes all expected fields
resp = JSON.parse(last_response.body)
[
  resp['record'].key?('orgid'),
  resp['record'].key?('display_name'),
  resp['record'].key?('description'),
  resp['record'].key?('contact_email'),
  resp['record'].key?('owner_id'),
  resp['record'].key?('member_count'),
  resp['record'].key?('created_at'),
  resp['record'].key?('updated_at')
]
#=> [true, true, true, true, true, true, true, true]

## Created organization has owner as member
resp = JSON.parse(last_response.body)
[resp['record']['current_user_role'], resp['record']['member_count']]
#=> ['owner', 1]

## Can list organizations for current user
get '/api/organizations',
  {},
  { 'rack.session' => @session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['records'].size > 0, resp.key?('count')]
#=> [200, true, true]

## Listed organizations include the created organization
resp = JSON.parse(last_response.body)
org_ids = resp['records'].map { |o| o['orgid'] }
org_ids.include?(@orgid)
#=> true

## Listed organizations have correct structure
resp = JSON.parse(last_response.body)
first_org = resp['records'].first
[
  first_org.key?('orgid'),
  first_org.key?('display_name'),
  first_org.key?('is_owner')
]
#=> [true, true, true]

## Can get organization details by orgid
get "/api/organizations/#{@orgid}",
  {},
  { 'rack.session' => @session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['orgid'], resp['record']['display_name']]
#=> [200, @orgid, 'API Test Org']

## Organization details include description and contact email
resp = JSON.parse(last_response.body)
[resp['record']['description'], resp['record']['contact_email'].include?('@example.com')]
#=> ['Created via API', true]

## Can update organization display name
put "/api/organizations/#{@orgid}",
  { display_name: 'Updated Org Name' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name']]
#=> [200, 'Updated Org Name']

## Can update organization description
put "/api/organizations/#{@orgid}",
  { description: 'New description' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['description']]
#=> [200, 'New description']

## Can update organization contact email
@new_email = "newemail#{Familia.now.to_i}@example.com"
put "/api/organizations/#{@orgid}",
  { contact_email: @new_email }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['contact_email']]
#=> [200, @new_email]

## Can update all fields at once
@final_email = "final#{Familia.now.to_i}@example.com"
put "/api/organizations/#{@orgid}",
  { display_name: 'Final Org Name', description: 'Final description', contact_email: @final_email }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name'], resp['record']['description'], resp['record']['contact_email']]
#=> [200, 'Final Org Name', 'Final description', @final_email]

## Updated timestamp changes after update
original_updated = JSON.parse(last_response.body)['record']['updated']
sleep 0.01
put "/api/organizations/#{@orgid}",
  { display_name: 'Timestamp Test' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
new_updated = JSON.parse(last_response.body)['record']['updated']
new_updated > original_updated
#=> true

## Cannot create organization without authentication
post '/api/organizations',
  { display_name: 'Unauthenticated Org', contact_email: 'test@example.com' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create organization without display name
post '/api/organizations',
  { description: 'Missing name', contact_email: "missing#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create organization without contact email
post '/api/organizations',
  { display_name: 'Missing Contact Email' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create organization with display name too long
long_name = 'A' * 101
post '/api/organizations',
  { display_name: long_name, contact_email: "toolong#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create organization with description too long
long_desc = 'A' * 501
post '/api/organizations',
  { display_name: 'Valid Name', description: long_desc, contact_email: "longdesc#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot get organization details without authentication
get "/api/organizations/#{@orgid}", {}, {}
last_response.status >= 400
#=> true

## Cannot update organization without authentication
put "/api/organizations/#{@orgid}",
  { display_name: 'Hacked Name' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot get non-existent organization
get "/api/organizations/nonexistent123",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Can delete organization
delete "/api/organizations/#{@orgid}",
  {},
  { 'rack.session' => @session }
last_response.status
#=> 200

## Deleted organization no longer accessible
get "/api/organizations/#{@orgid}",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Cannot delete already deleted organization
delete "/api/organizations/#{@orgid}",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Cannot delete organization without authentication
post '/api/organizations',
  { display_name: 'Delete Test Org', contact_email: "deletetest#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
@delete_orgid = JSON.parse(last_response.body)['record']['orgid']
delete "/api/organizations/#{@delete_orgid}", {}, {}
[last_response.status >= 400, @delete_orgid != nil]
#=> [true, true]

# Cleanup the test organization we just created
@org_to_cleanup = Onetime::Organization.load(@delete_orgid)
@org_to_cleanup.destroy! if @org_to_cleanup

# Teardown
@cust.destroy!
