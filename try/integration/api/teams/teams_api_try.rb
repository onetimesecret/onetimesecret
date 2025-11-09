# try/integration/api/teams/teams_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for Teams CRUD API endpoints:
# - POST /api/teams (create team)
# - GET /api/teams (list user's teams)
# - GET /api/teams/:teamid (get team details)
# - PUT /api/teams/:teamid (update team)
# - DELETE /api/teams/:teamid (delete team)

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

## Can create team via API - check status first
post '/api/teams',
  { display_name: 'API Test Team', description: 'Created via API' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Can parse create team response
resp = JSON.parse(last_response.body)
@teamid = resp['record']['teamid']
[resp['record']['display_name'], resp['record']['owner_id']]
#=> ['API Test Team', @cust.custid]

## Created team response includes all expected fields
resp = JSON.parse(last_response.body)
[
  resp['record'].key?('teamid'),
  resp['record'].key?('display_name'),
  resp['record'].key?('description'),
  resp['record'].key?('owner_id'),
  resp['record'].key?('is_owner'),
  resp['record'].key?('member_count'),
  resp['record'].key?('created'),
  resp['record'].key?('updated')
]
#=> [true, true, true, true, true, true, true, true]

## Created team has owner as member
resp = JSON.parse(last_response.body)
[resp['record']['is_owner'], resp['record']['member_count']]
#=> [true, 1]

## Can list teams for current user
get '/api/teams',
  {},
  { 'rack.session' => @session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['records'].size > 0, resp.key?('count')]
#=> [200, true, true]

## Listed teams include the created team
resp = JSON.parse(last_response.body)
team_ids = resp['records'].map { |t| t['teamid'] }
team_ids.include?(@teamid)
#=> true

## Listed teams have correct structure
resp = JSON.parse(last_response.body)
first_team = resp['records'].first
[
  first_team.key?('teamid'),
  first_team.key?('display_name'),
  first_team.key?('is_owner')
]
#=> [true, true, true]

## Can get team details by teamid
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['teamid'], resp['record']['display_name']]
#=> [200, @teamid, 'API Test Team']

## Team details include description
resp = JSON.parse(last_response.body)
resp['record']['description']
#=> 'Created via API'

## Can update team display name
put "/api/teams/#{@teamid}",
  { display_name: 'Updated Team Name' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name']]
#=> [200, 'Updated Team Name']

## Can update team description
put "/api/teams/#{@teamid}",
  { description: 'New description' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['description']]
#=> [200, 'New description']

## Can update both display name and description
put "/api/teams/#{@teamid}",
  { display_name: 'Final Team Name', description: 'Final description' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name'], resp['record']['description']]
#=> [200, 'Final Team Name', 'Final description']

## Updated timestamp changes after update
original_updated = JSON.parse(last_response.body)['record']['updated']
sleep 0.01
put "/api/teams/#{@teamid}",
  { display_name: 'Timestamp Test' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
new_updated = JSON.parse(last_response.body)['record']['updated']
new_updated > original_updated
#=> true

## Cannot create team without authentication
post '/api/teams',
  { display_name: 'Unauthenticated Team' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create team without display name
post '/api/teams',
  { description: 'Missing name' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create team with display name too short
post '/api/teams',
  { display_name: 'AB' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create team with display name too long
long_name = 'A' * 101
post '/api/teams',
  { display_name: long_name }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot create team with description too long
long_desc = 'A' * 501
post '/api/teams',
  { display_name: 'Valid Name', description: long_desc }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot get team details without authentication
get "/api/teams/#{@teamid}", {}, {}
last_response.status >= 400
#=> true

## Cannot update team without authentication
put "/api/teams/#{@teamid}",
  { display_name: 'Hacked Name' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot get non-existent team
get "/api/teams/nonexistent123",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Can delete team
delete "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @session }
last_response.status
#=> 200

## Deleted team no longer accessible
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Cannot delete already deleted team
delete "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @session }
last_response.status >= 400
#=> true

## Cannot delete team without authentication
post '/api/teams',
  { display_name: 'Delete Test Team' }.to_json,
  { 'rack.session' => @session, 'CONTENT_TYPE' => 'application/json' }
delete_teamid = JSON.parse(last_response.body)['record']['teamid']
delete "/api/teams/#{delete_teamid}", {}, {}
[last_response.status >= 400, delete_teamid != nil]
#=> [true, true]

# Cleanup the test team we just created
@team_to_cleanup = Onetime::Team.load(delete_teamid)
@team_to_cleanup.destroy! if @team_to_cleanup

# Teardown
@cust.destroy!
