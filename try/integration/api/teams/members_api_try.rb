# try/integration/api/teams/members_api_try.rb
#
# Integration tests for Team Members API endpoints:
# - GET /api/teams/:teamid/members (list members)
# - POST /api/teams/:teamid/members (add member)
# - DELETE /api/teams/:teamid/members/:custid (remove member)

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
@owner = Onetime::Customer.create!(email: "owner#{Familia.now.to_i}@onetimesecret.com")
@member1 = Onetime::Customer.create!(email: "member1#{Familia.now.to_i}@onetimesecret.com")
@member2 = Onetime::Customer.create!(email: "member2#{Familia.now.to_i}@onetimesecret.com")
@non_member = Onetime::Customer.create!(email: "nonmember#{Familia.now.to_i}@onetimesecret.com")

@owner_session = { 'authenticated' => true, 'external_id' => @owner.extid, 'email' => @owner.email }
@member1_session = { 'authenticated' => true, 'external_id' => @member1.extid, 'email' => @member1.email }
@member2_session = { 'authenticated' => true, 'external_id' => @member2.extid, 'email' => @member2.email }
@non_member_session = { 'authenticated' => true, 'external_id' => @non_member.extid, 'email' => @non_member.email }

# Create team manually (Team.create! has a bug)
@team = Onetime::Team.new(display_name: "Members Test Team", owner_id: @owner.custid)
@team.save
@team.members.add(@owner.objid, Familia.now.to_f)
@teamid = @team.teamid

## Can list team members
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['records'].size, resp.key?('count')]
#=> [200, 1, true]

## Initial member list includes owner
resp = JSON.parse(last_response.body)
members = resp['records']
members.first['custid']
#=> @owner.custid

## Member record has expected fields
resp = JSON.parse(last_response.body)
member = resp['records'].first
[
  member.key?('custid'),
  member.key?('email'),
  member.key?('display_name')
]
#=> [true, true, true]

## Can add member to team by email
post "/api/teams/#{@teamid}/members",
  { email: @member1.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['custid'], resp['record']['email']]
#=> [200, @member1.custid, @member1.email]

## Member list grows after adding member
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['count']
#=> 2

## Added member appears in member list
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['custid'] }
member_ids.include?(@member1.custid)
#=> true

## Can add multiple members
post "/api/teams/#{@teamid}/members",
  { email: @member2.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['count']
#=> 3

## Cannot add member without authentication
post "/api/teams/#{@teamid}/members",
  { email: @non_member.email }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member without email
post "/api/teams/#{@teamid}/members",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member with invalid email format
post "/api/teams/#{@teamid}/members",
  { email: 'not-an-email' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member with non-existent email
post "/api/teams/#{@teamid}/members",
  { email: 'nonexistent@example.com' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add duplicate member
post "/api/teams/#{@teamid}/members",
  { email: @member1.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Non-owner cannot add members
post "/api/teams/#{@teamid}/members",
  { email: @non_member.email }.to_json,
  { 'rack.session' => { custid: @member1.custid }, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Members can list team members
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @member1_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['count']]
#=> [200, 3]

## Non-members cannot list team members
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @non_member_session }
last_response.status >= 400
#=> true

## Can remove member from team
delete "/api/teams/#{@teamid}/members/#{@member2.custid}",
  {},
  { 'rack.session' => @owner_session }
last_response.status
#=> 200

## Member list shrinks after removing member
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['count']
#=> 2

## Removed member not in member list
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['custid'] }
member_ids.include?(@member2.custid)
#=> false

## Cannot remove member without authentication
delete "/api/teams/#{@teamid}/members/#{@member1.custid}",
  {},
  {}
last_response.status >= 400
#=> true

## Non-owner cannot remove members
delete "/api/teams/#{@teamid}/members/#{@member1.custid}",
  {},
  { 'rack.session' => @member1_session }
last_response.status >= 400
#=> true

## Cannot remove non-existent member
delete "/api/teams/#{@teamid}/members/nonexistent123",
  {},
  { 'rack.session' => @owner_session }
last_response.status >= 400
#=> true

## Cannot remove member from non-existent team
delete "/api/teams/nonexistent123/members/#{@member1.custid}",
  {},
  { 'rack.session' => @owner_session }
last_response.status >= 400
#=> true

## Owner can remove themselves from team
initial_count = @team.member_count
delete "/api/teams/#{@teamid}/members/#{@owner.custid}",
  {},
  { 'rack.session' => @owner_session }
[last_response.status, @team.member_count]
#=> [200, initial_count - 1]

## Removed owner no longer in member list
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @member1_session }
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['custid'] }
member_ids.include?(@owner.custid)
#=> false

## Owner can still access team even after removing themselves as member
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['teamid']]
#=> [200, @teamid]

## Owner can add themselves back as member
post "/api/teams/#{@teamid}/members",
  { email: @owner.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['custid']]
#=> [200, @owner.custid]

# Teardown
@team.destroy!
@owner.destroy!
@member1.destroy!
@member2.destroy!
@non_member.destroy!
