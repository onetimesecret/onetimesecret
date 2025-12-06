# try/integration/api/teams/members_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for Team Members API endpoints:
# - GET /api/teams/:extid/members (list members)
# - POST /api/teams/:extid/members (add member)
# - DELETE /api/teams/:extid/members/:custid (remove member)

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
@owner = Onetime::Customer.create!(email: generate_unique_test_email("members_owner"))
@member1 = Onetime::Customer.create!(email: generate_unique_test_email("members_member1"))
@member2 = Onetime::Customer.create!(email: generate_unique_test_email("members_member2"))
@non_member = Onetime::Customer.create!(email: generate_unique_test_email("members_nonmember"))

@owner_session = { 'authenticated' => true, 'external_id' => @owner.extid, 'email' => @owner.email }
@member1_session = { 'authenticated' => true, 'external_id' => @member1.extid, 'email' => @member1.email }
@member2_session = { 'authenticated' => true, 'external_id' => @member2.extid, 'email' => @member2.email }
@non_member_session = { 'authenticated' => true, 'external_id' => @non_member.extid, 'email' => @non_member.email }

# Create team manually (Team.create! has a bug)
@team = Onetime::Team.new(display_name: "Members Test Team", owner_id: @owner.custid)
@team.save
@team.members.add(@owner.objid, Familia.now.to_f)
@team_id = @team.extid  # Use extid for API calls, not objid

## Can list team members
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['records'].size, resp.key?('count')]
#=> [200, 1, true]

## Initial member list includes owner
resp = JSON.parse(last_response.body)
members = resp['records']
members.first['id']  # API returns 'id' not 'custid'
#=> @owner.custid

## Member record has expected fields
resp = JSON.parse(last_response.body)
member = resp['records'].first
[
  member.key?('id'),  # API uses 'id' not 'custid'
  member.key?('email'),
  member.key?('role')  # API returns 'role' not 'display_name'
]
#=> [true, true, true]

## Can add member to team by email
post "/api/teams/#{@team_id}/members",
  { email: @member1.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['id'], resp['record']['email']]  # API uses 'id' not 'custid'
#=> [200, @member1.custid, @member1.email]

## Member list grows after adding member
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['count']
#=> 2

## Added member appears in member list
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['id'] }  # API uses 'id' not 'custid'
member_ids.include?(@member1.custid)
#=> true

## Can add multiple members
post "/api/teams/#{@team_id}/members",
  { email: @member2.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['count']
#=> 3

## Cannot add member without authentication
post "/api/teams/#{@team_id}/members",
  { email: @non_member.email }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member without email
post "/api/teams/#{@team_id}/members",
  {}.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member with invalid email format
post "/api/teams/#{@team_id}/members",
  { email: 'not-an-email' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member with non-existent email
post "/api/teams/#{@team_id}/members",
  { email: 'nonexistent@example.com' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add duplicate member
post "/api/teams/#{@team_id}/members",
  { email: @member1.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Non-owner cannot add members
post "/api/teams/#{@team_id}/members",
  { email: @non_member.email }.to_json,
  { 'rack.session' => { custid: @member1.custid }, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Members can list team members
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @member1_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['count']]
#=> [200, 3]

## Non-members cannot list team members
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @non_member_session }
last_response.status >= 400
#=> true

## Can remove member from team
delete "/api/teams/#{@team_id}/members/#{@member2.custid}",
  {},
  { 'rack.session' => @owner_session }
last_response.status
#=> 200

## Member list shrinks after removing member
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
resp['count']
#=> 2

## Removed member not in member list
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['id'] }  # API uses 'id' not 'custid'
member_ids.include?(@member2.custid)
#=> false

## Cannot remove member without authentication
delete "/api/teams/#{@team_id}/members/#{@member1.custid}",
  {},
  {}
last_response.status >= 400
#=> true

## Non-owner cannot remove OTHER members (but can remove themselves)
# member1 tries to remove owner - should fail since member1 is not the owner
delete "/api/teams/#{@team_id}/members/#{@owner.custid}",
  {},
  { 'rack.session' => @member1_session }
last_response.status >= 400
#=> true

## Cannot remove non-existent member
delete "/api/teams/#{@team_id}/members/nonexistent123",
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

## Owner CANNOT remove themselves from team (API design: teams must have an owner)
@initial_member_count = @team.member_count
delete "/api/teams/#{@team_id}/members/#{@owner.custid}",
  {},
  { 'rack.session' => @owner_session }
[last_response.status >= 400, @team.member_count]  # Should fail, member count unchanged
#=> [true, @initial_member_count]

## Owner is still in member list after failed removal
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
member_ids = resp['records'].map { |m| m['id'] }  # API uses 'id' not 'custid'
member_ids.include?(@owner.custid)
#=> true

## Owner can still access team
get "/api/teams/#{@team_id}",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
[last_response.status, resp['record']['extid']]
#=> [200, @team_id]

## Regular member can remove themselves from team
delete "/api/teams/#{@team_id}/members/#{@member1.custid}",
  {},
  { 'rack.session' => @member1_session }
last_response.status
#=> 200

# ============================================================================
# POST-REMOVAL BEHAVIOR TESTS
# ============================================================================

## Member loses list access after self-removal
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @member1_session }
last_response.status >= 400  # member1 removed themselves, should no longer have access
#=> true

## Can re-add a previously removed member
post "/api/teams/#{@team_id}/members",
  { email: @member1.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
[last_response.status, JSON.parse(last_response.body)['record']['id']]
#=> [200, @member1.custid]

## Re-added member can list team members again
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @member1_session }
last_response.status
#=> 200

# ============================================================================
# RESPONSE FORMAT VALIDATION TESTS
# ============================================================================

## Member record contains all expected fields
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
member = resp['records'].first
required_fields = %w[id team_extid user_id email role status created_at updated_at]
required_fields.all? { |f| member.key?(f) }
#=> true

## Owner has 'owner' role in member list
get "/api/teams/#{@team_id}/members",
  {},
  { 'rack.session' => @owner_session }
resp = JSON.parse(last_response.body)
owner_record = resp['records'].find { |m| m['id'] == @owner.custid }
owner_record['role']
#=> 'owner'

## Regular member has 'member' role in member list
resp = JSON.parse(last_response.body)
member_record = resp['records'].find { |m| m['id'] == @member1.custid }
member_record['role']
#=> 'member'

## Count field matches records array length
resp = JSON.parse(last_response.body)
resp['count'] == resp['records'].length
#=> true

## Error response returns 4xx status for invalid input
post "/api/teams/#{@team_id}/members",
  { email: 'invalid' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
# Note: Error responses may be plain text (FormError) rather than JSON
# Testing that we get an error status, not the exact format
[last_response.status >= 400, last_response.body.length > 0]
#=> [true, true]

# ============================================================================
# EDGE CASE TESTS
# ============================================================================

## Email lookup is case-insensitive
@case_test_member = Onetime::Customer.create!(email: generate_unique_test_email("members_case"))
post "/api/teams/#{@team_id}/members",
  { email: @case_test_member.email.upcase }.to_json,  # Send uppercase email
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
[last_response.status, JSON.parse(last_response.body)['record']['email']]
#=> [200, @case_test_member.email]

## Whitespace-only email is rejected
post "/api/teams/#{@team_id}/members",
  { email: '   ' }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Adding owner (already a member) is rejected as duplicate
post "/api/teams/#{@team_id}/members",
  { email: @owner.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

## Cannot add member to team where you're not the owner
# Create a second team owned by member1
@team2 = Onetime::Team.new(display_name: "Second Team", owner_id: @member1.custid)
@team2.save
@team2.members.add(@member1.objid, Familia.now.to_f)
# Owner of team1 tries to add someone to team2 (which they don't own)
post "/api/teams/#{@team2.extid}/members",
  { email: @non_member.email }.to_json,
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/json' }
last_response.status >= 400
#=> true

# ============================================================================
# CONTENT-TYPE HANDLING TESTS
# ============================================================================

## POST without Content-Type header is rejected or handled gracefully
post "/api/teams/#{@team_id}/members",
  { email: @non_member.email }.to_json,
  { 'rack.session' => @owner_session }  # No CONTENT_TYPE
# Should either fail (400+) or succeed - but not crash (500)
last_response.status != 500
#=> true

## POST with form-encoded Content-Type also works (API is flexible)
post "/api/teams/#{@team_id}/members",
  "email=#{@non_member.email}",  # Form-encoded data
  { 'rack.session' => @owner_session, 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
# API accepts both JSON and form-encoded data
last_response.status
#=> 200

# Teardown
@team2.destroy!
@team.destroy!
@case_test_member.destroy!
@owner.destroy!
@member1.destroy!
@member2.destroy!
@non_member.destroy!
