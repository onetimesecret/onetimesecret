# try/integration/api/organizations/organizations_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for Organizations CRUD API endpoints:
# - POST /api/organizations (create organization)
# - GET /api/organizations (list user's organizations)
# - GET /api/organizations/:extid (get organization details)
# - PUT /api/organizations/:extid (update organization)
# - DELETE /api/organizations/:extid (delete organization)

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
@cust = Onetime::Customer.create!(email: generate_unique_test_email("orgs_api"))
@session = { 'authenticated' => true, 'external_id' => @cust.extid, 'email' => @cust.email }

## Can create organization via API - check status first
post '/api/organizations',
  { display_name: 'API Test Org', description: 'Created via API', contact_email: "contact#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Can parse create organization response
resp = JSON.parse(last_response.body)
@extid = resp['record']['id']
[resp['record']['display_name'], resp['record']['owner_id']]
#=> ['API Test Org', @cust.custid]

## Created organization response includes all expected fields
resp = JSON.parse(last_response.body)
[
  resp['record'].key?('id'),
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
org_ids = resp['records'].map { |o| o['id'] }
org_ids.include?(@extid)
#=> true

## Listed organizations have correct structure
resp = JSON.parse(last_response.body)
first_org = resp['records'].first
[
  first_org.key?('id'),
  first_org.key?('display_name'),
  first_org.key?('current_user_role')
]
#=> [true, true, true]

## Can get organization details by external identifier
get "/api/organizations/#{@extid}",
  {},
  { 'rack.session' => @session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['id'], resp['record']['display_name']]
#=> [200, @extid, 'API Test Org']

## Organization details include description and contact email
resp = JSON.parse(last_response.body)
[resp['record']['description'], resp['record']['contact_email'].include?('@example.com')]
#=> ['Created via API', true]

## Can update organization display name
put "/api/organizations/#{@extid}",
  { display_name: 'Updated Org Name' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name']]
#=> [200, 'Updated Org Name']

## Can update organization description
put "/api/organizations/#{@extid}",
  { description: 'New description' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['description']]
#=> [200, 'New description']

## Can update organization contact email
@new_email = "newemail#{Familia.now.to_i}@example.com"
put "/api/organizations/#{@extid}",
  { contact_email: @new_email }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['contact_email']]
#=> [200, @new_email]

## Can update all fields at once
@final_email = "final#{Familia.now.to_i}@example.com"
put "/api/organizations/#{@extid}",
  { display_name: 'Final Org Name', description: 'Final description', contact_email: @final_email }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name'], resp['record']['description'], resp['record']['contact_email']]
#=> [200, 'Final Org Name', 'Final description', @final_email]

## Updated timestamp changes after update
original_updated = JSON.parse(last_response.body)['record']['updated_at']
sleep 0.01
put "/api/organizations/#{@extid}",
  { display_name: 'Timestamp Test' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
new_updated = JSON.parse(last_response.body)['record']['updated_at']
new_updated > original_updated
#=> true

## Cannot create organization without authentication
# Clear cookies to simulate a truly unauthenticated request
@test.rack_mock_session.cookie_jar.clear
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

## Can create organization without contact email (optional field)
post '/api/organizations',
  { display_name: 'No Contact Email Org' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
@no_email_extid = JSON.parse(last_response.body)['record']['id'] rescue nil
last_response.status
#=> 200

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
# Clear cookies to simulate a truly unauthenticated request
@test.rack_mock_session.cookie_jar.clear
get "/api/organizations/#{@extid}", {}, {}
last_response.status >= 400
#=> true

## Cannot update organization without authentication
# Clear cookies to simulate a truly unauthenticated request
@test.rack_mock_session.cookie_jar.clear
put "/api/organizations/#{@extid}",
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
delete "/api/organizations/#{@extid}",
  {},
  { 'rack.session' => @session }
last_response.status
#=> 200

## Deleted organization no longer accessible
get "/api/organizations/#{@extid}",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Cannot delete already deleted organization
delete "/api/organizations/#{@extid}",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Cannot delete organization without authentication
post '/api/organizations',
  { display_name: 'Delete Test Org', contact_email: "deletetest#{Familia.now.to_i}@example.com" }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
@delete_extid = JSON.parse(last_response.body)['record']['id']
# Clear cookies to simulate a truly unauthenticated request
@test.rack_mock_session.cookie_jar.clear
delete "/api/organizations/#{@delete_extid}", {}, {}
[last_response.status >= 400, @delete_extid != nil]
#=> [true, true]

# Cleanup the test organizations we created
@org_to_cleanup = Onetime::Organization.find_by_extid(@delete_extid)
@org_to_cleanup.destroy! if @org_to_cleanup
@no_email_org = Onetime::Organization.find_by_extid(@no_email_extid)
@no_email_org.destroy! if @no_email_org

# Teardown
@cust.destroy!
