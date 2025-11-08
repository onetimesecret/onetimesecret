# try/integration/api/teams/authorization_try.rb
#
# frozen_string_literal: true

#
# Integration tests for Teams authorization and permissions:
# - Non-owner cannot update team
# - Non-owner cannot delete team
# - Non-member cannot view team
# - Owner can remove members
# - Member can view but not modify
# - Team isolation between users

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
@owner = Onetime::Customer.create!(email: "authowner#{Familia.now.to_i}@onetimesecret.com")
@member = Onetime::Customer.create!(email: "authmember#{Familia.now.to_i}@onetimesecret.com")
@outsider = Onetime::Customer.create!(email: "outsider#{Familia.now.to_i}@onetimesecret.com")

@owner_session = { 'authenticated' => true, 'external_id' => @owner.extid, 'email' => @owner.email }
@member_session = { 'authenticated' => true, 'external_id' => @member.extid, 'email' => @member.email }
@outsider_session = { 'authenticated' => true, 'external_id' => @outsider.extid, 'email' => @outsider.email }

# Create team manually (Team.create! has a bug)
@team = Onetime::Team.new(display_name: "Authorization Test Team", owner_id: @owner.custid)
@team.save
@team.members.add(@owner.objid, Familia.now.to_f)
@team.members.add(@member.objid, Familia.now.to_f)
@teamid = @team.teamid

## Owner can view their team
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['teamid']]
#=> [200, @teamid]

## Owner is marked as owner in team response
resp = JSON.parse(last_response.body)
resp['record']['is_owner']
#=> true

## Member can view team
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @member_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['teamid']]
#=> [200, @teamid]

## Member is not marked as owner in team response
resp = JSON.parse(last_response.body)
resp['record']['is_owner']
#=> false

## Non-member cannot view team
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @outsider_session }
last_response.status >= 400
#=> true

## Owner can update team
put "/api/teams/#{@teamid}",
  { display_name: 'Owner Updated Name' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['display_name']]
#=> [200, 'Owner Updated Name']

## Member cannot update team
put "/api/teams/#{@teamid}",
  { display_name: 'Member Attempted Update' }.to_json,
  { 'rack.session' => @member_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Team name unchanged after member update attempt
get "/api/teams/#{@teamid}",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['record']['display_name']
#=> 'Owner Updated Name'

## Non-member cannot update team
put "/api/teams/#{@teamid}",
  { display_name: 'Outsider Attempted Update' }.to_json,
  { 'rack.session' => @outsider_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Owner can delete team
@delete_test_team = Onetime::Team.create!("Delete Auth Test", @owner)
delete_teamid = @delete_test_team.teamid
delete "/api/teams/#{delete_teamid}",
  {},
  { 'rack.session' => @owner_session }
last_response.status
#=> 200

## Member cannot delete team
@member_delete_team = Onetime::Team.create!("Member Delete Test", @owner)
@member_delete_team.add_member(@member, 'member')
member_delete_teamid = @member_delete_team.teamid
delete "/api/teams/#{member_delete_teamid}",
  {},
  { 'rack.session' => @member_session }
[last_response.status >= 400, @member_delete_team.teamid != nil]
#=> [true, true]

## Team still exists after member delete attempt
get "/api/teams/#{member_delete_teamid}",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['teamid']]
#=> [200, member_delete_teamid]

# Cleanup the test team
@member_delete_team.destroy!

## Non-member cannot delete team
@outsider_delete_team = Onetime::Team.create!("Outsider Delete Test", @owner)
outsider_delete_teamid = @outsider_delete_team.teamid
delete "/api/teams/#{outsider_delete_teamid}",
  {},
  { 'rack.session' => @outsider_session }
[last_response.status >= 400, @outsider_delete_team.teamid != nil]
#=> [true, true]

# Cleanup the test team
@outsider_delete_team.destroy!

## Owner can add members
post "/api/teams/#{@teamid}/members",
  { email: @outsider.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status
#=> 200

## Member cannot add members
@new_user = Onetime::Customer.create!(email: "newuser#{Familia.now.to_i}@onetimesecret.com")
post "/api/teams/#{@teamid}/members",
  { email: @new_user.email }.to_json,
  { 'rack.session' => @member_session, 'CONTENT_TYPE' => 'application/json' }
[last_response.status >= 400, @new_user.custid != nil]
#=> [true, true]

## New user not added after member attempt
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['custid'] }
member_ids.include?(@new_user.custid)
#=> false

# Cleanup
@new_user.destroy!

## Non-member cannot add members
@another_user = Onetime::Customer.create!(email: "anotheruser#{Familia.now.to_i}@onetimesecret.com")
@outsider_team = Onetime::Team.create!("Outsider Team", @outsider)
outsider_team_id = @outsider_team.teamid
post "/api/teams/#{@teamid}/members",
  { email: @another_user.email }.to_json,
  { 'rack.session' => @outsider_session, 'CONTENT_TYPE' => 'application/json' }
[last_response.status >= 400, @another_user.custid != nil]
#=> [true, true]

# Cleanup
@another_user.destroy!
@outsider_team.destroy!

## Owner can remove members
delete "/api/teams/#{@teamid}/members/#{@member.custid}",
  {},
  { 'rack.session' => @owner_session }
last_response.status
#=> 200

## Member cannot remove other members
@team.add_member(@member, 'member')
@another_member = Onetime::Customer.create!(email: "anothermember#{Familia.now.to_i}@onetimesecret.com")
@team.add_member(@another_member, 'member')
delete "/api/teams/#{@teamid}/members/#{@another_member.custid}",
  {},
  { 'rack.session' => @member_session }
[last_response.status >= 400, @another_member.custid != nil]
#=> [true, true]

## Other member still in team after removal attempt
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['custid'] }
member_ids.include?(@another_member.custid)
#=> true

# Cleanup
@another_member.destroy!

## Non-member cannot remove members
@outsider_member = Onetime::Customer.create!(email: "outsidermember#{Familia.now.to_i}@onetimesecret.com")
@team.add_member(@outsider_member, 'member')
delete "/api/teams/#{@teamid}/members/#{@outsider_member.custid}",
  {},
  { 'rack.session' => @outsider_session }
[last_response.status >= 400, @outsider_member.custid != nil]
#=> [true, true]

# Cleanup
@outsider_member.destroy!

## Teams are isolated - user cannot see other user's teams
@user1 = Onetime::Customer.create!(email: "isolation1#{Familia.now.to_i}@onetimesecret.com")
@user2 = Onetime::Customer.create!(email: "isolation2#{Familia.now.to_i}@onetimesecret.com")
@user1_session = { 'authenticated' => true, 'external_id' => @user1.extid, 'email' => @user1.email }
@user2_session = { 'authenticated' => true, 'external_id' => @user2.extid, 'email' => @user2.email }
@user1_team = Onetime::Team.create!("User 1 Team", @user1)
@user2_team = Onetime::Team.create!("User 2 Team", @user2)
get '/api/teams',
  {},
  { 'rack.session' => @user1_session }
resp = JSON.parse(last_response.body)
team_ids = resp['records'].map { |t| t['teamid'] }
[team_ids.include?(@user1_team.teamid), team_ids.include?(@user2_team.teamid)]
#=> [true, false]

## User 2 cannot access User 1's team
get "/api/teams/#{@user1_team.teamid}",
  {},
  { 'rack.session' => @user2_session }
last_response.status >= 400
#=> true

## User 1 cannot access User 2's team
get "/api/teams/#{@user2_team.teamid}",
  {},
  { 'rack.session' => @user1_session }
last_response.status >= 400
#=> true

# Cleanup isolation test
@user1_team.destroy!
@user2_team.destroy!
@user1.destroy!
@user2.destroy!

## Member can list members
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @member_session }
last_response.status
#=> 200

## Non-member cannot list members
get "/api/teams/#{@teamid}/members",
  {},
  { 'rack.session' => @outsider_session }
last_response.status >= 400
#=> true

## Anonymous user cannot access any team endpoints
get "/api/teams", {}, {}
[last_response.status >= 400]
#=> [true]

## Anonymous user cannot view team
get "/api/teams/#{@teamid}", {}, {}
last_response.status >= 400
#=> true

## Anonymous user cannot list members
get "/api/teams/#{@teamid}/members", {}, {}
last_response.status >= 400
#=> true

# Teardown
@team.destroy!
@owner.destroy!
@member.destroy!
@outsider.destroy!
