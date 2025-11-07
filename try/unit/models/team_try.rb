# try/unit/models/team_try.rb
#
# Unit tests for the Onetime::Team model.
# Tests cover:
# - Team creation with owner
# - Owner management methods
# - Member management (add, remove, check, list)
# - Member count tracking
# - Authorization helpers (can_modify?, can_delete?)
# - Factory method validation

require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

# Setup test data
@owner = Onetime::Customer.create!(email: "owner#{Familia.now.to_i}@onetimesecret.com")
@member1 = Onetime::Customer.create!(email: "member1#{Familia.now.to_i}@onetimesecret.com")
@member2 = Onetime::Customer.create!(email: "member2#{Familia.now.to_i}@onetimesecret.com")
@non_member = Onetime::Customer.create!(email: "nonmember#{Familia.now.to_i}@onetimesecret.com")

# Create team using factory method (Familia v2 auto-manages instances and relationships)
@team = Onetime::Team.create!("Engineering Team", @owner)

## Can create team manually
[@team.class, @team.display_name, @team.owner_id]
#=> [Onetime::Team, "Engineering Team", @owner.custid]

## Team has a valid teamid (UUUID format - Familia.generate_id)
@team.teamid.class
#=> String

## Team owner is correctly set
@team.owner.custid
#=> @owner.custid

## Owner check returns true for team owner
@team.owner?(@owner)
#=> true

## Owner check returns false for non-owner
@team.owner?(@member1)
#=> false

## Owner check handles nil customer (returns nil instead of false)
@team.owner?(nil)
#=> nil

## Team owner is automatically added as first member
@team.member?(@owner)
#=> true

## Initial member count is 1 (owner only)
@team.member_count
#=> 1

## Can add member to team (using Familia v2 relationship)
@team.add_member(@member1)
@team.member?(@member1)
#=> true

## Member count updates after adding member
@team.member_count
#=> 2

## Can add multiple members (using Familia v2 relationship)
@team.add_member(@member2)
[@team.member?(@member2), @team.member_count]
#=> [true, 3]

## Non-member check returns false
@team.member?(@non_member)
#=> false

## Member check returns false for nil customer
@team.member?(nil)
#=> false

## List members returns all team members
members = @team.list_members
[members.size, members.map(&:custid).sort]
#=> [3, [@owner.custid, @member1.custid, @member2.custid].sort]

## List members returns Customer objects
@team.list_members.first.class
#=> Onetime::Customer

## Can remove member from team
@team.remove_member(@member2)
@team.member?(@member2)
#=> false

## Member count updates after removing member
@team.member_count
#=> 2

## Removed member not in members list
@team.list_members.map(&:custid).include?(@member2.custid)
#=> false

## Owner can modify team
@team.can_modify?(@owner)
#=> true

## Non-owner cannot modify team
@team.can_modify?(@member1)
#=> false

## Can modify handles nil customer (returns nil via owner?)
@team.can_modify?(nil)
#=> nil

## Owner can delete team
@team.can_delete?(@owner)
#=> true

## Non-owner cannot delete team
@team.can_delete?(@member1)
#=> false

## Can delete handles nil customer (returns nil via owner?)
@team.can_delete?(nil)
#=> nil

## Factory method requires owner
begin
  Onetime::Team.create!("Invalid Team", nil)
rescue Onetime::Problem => e
  e.message
end
#=> "Owner required"

## Factory method requires display name
begin
  Onetime::Team.create!("", @owner)
rescue Onetime::Problem => e
  e.message
end
#=> "Display name required"

## Factory method requires non-empty display name
begin
  Onetime::Team.create!("   ", @owner)
rescue Onetime::Problem => e
  e.message
end
#=> "Display name required"

## Can set team description
@team.description = "Our engineering team"
@team.save
@team.description
#=> "Our engineering team"

## Can update team display name
@team.display_name = "Platform Engineering"
@team.save
@team.display_name
#=> "Platform Engineering"

## Team has created timestamp (Familia v2 uses Float for timestamps)
@team.created.class
#=> Float

## Team has updated timestamp (Familia v2 uses Float for timestamps)
@team.updated.class
#=> Float

## Updated timestamp changes when team is modified
original_updated = @team.updated
sleep 0.01
@team.display_name = "Updated Team Name"
@team.save
@team.updated > original_updated
#=> true

## Can load team by teamid
loaded_team = Onetime::Team.load(@team.teamid)
[loaded_team.teamid, loaded_team.display_name]
#=> [@team.teamid, "Updated Team Name"]

## Loading non-existent team returns nil
Onetime::Team.load("nonexistent123")
#=> nil

# Teardown
@team.destroy!
@owner.destroy!
@member1.destroy!
@member2.destroy!
@non_member.destroy!
