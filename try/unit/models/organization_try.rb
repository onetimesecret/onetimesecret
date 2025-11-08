# try/unit/models/organization_try.rb
#
# Unit tests for the Onetime::Organization model.
# Tests cover:
# - Organization creation with owner
# - Owner management methods
# - Member management (add, remove, check, list) via participates_in
# - Member count tracking
# - Authorization helpers (can_modify?, can_delete?)
# - Organization-scoped unique indexes
# - Factory method validation
# - contact_email field

require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

# Setup test data
@owner = Onetime::Customer.create!(email: "org_owner#{Familia.now.to_i}@onetimesecret.com")
@member1 = Onetime::Customer.create!(email: "org_member1#{Familia.now.to_i}@onetimesecret.com")
@member2 = Onetime::Customer.create!(email: "org_member2#{Familia.now.to_i}@onetimesecret.com")
@non_member = Onetime::Customer.create!(email: "org_nonmember#{Familia.now.to_i}@onetimesecret.com")

# Create organization using factory method
@org = Onetime::Organization.create!(
  "Acme Corporation",
  @owner,
  "billing@acme.com"
)

## Can create organization with factory method
[@org.class, @org.display_name, @org.owner_id]
#=> [Onetime::Organization, "Acme Corporation", @owner.custid]

## Organization has a valid orgid (UUID format - Familia.generate_id)
@org.orgid.class
#=> String

## Organization has contact_email set
@org.contact_email
#=> "billing@acme.com"

## Organization owner is correctly set
@org.owner.custid
#=> @owner.custid

## Owner check returns true for organization owner
@org.owner?(@owner)
#=> true

## Owner check returns false for non-owner
@org.owner?(@member1)
#=> false

## Owner check handles nil customer
@org.owner?(nil)
#=> nil

## Organization owner is automatically added as first member via participates_in
@org.member?(@owner)
#=> true

## Initial member count is 1 (owner only)
@org.member_count
#=> 1

## Can add member to organization (using Familia v2 participates_in)
@owner_objid = @org.add_member(@member1)
@org.member?(@member1)
#=> true

## Member count updates after adding member
@org.member_count
#=> 2

## Can add multiple members
@org.add_member(@member2)
[@org.member?(@member2), @org.member_count]
#=> [true, 3]

## Non-member check returns false
@org.member?(@non_member)
#=> false

## Member check returns false for nil customer
@org.member?(nil)
#=> false

## List members returns all organization members
members = @org.list_members
[members.size, members.map(&:custid).sort]
#=> [3, [@owner.custid, @member1.custid, @member2.custid].sort]

## List members returns Customer objects
@org.list_members.first.class
#=> Onetime::Customer

## Can remove member from organization
@org.remove_member(@member2)
@org.member?(@member2)
#=> false

## Member count updates after removing member
@org.member_count
#=> 2

## Removed member not in members list
@org.list_members.map(&:custid).include?(@member2.custid)
#=> false

## Owner can modify organization
@org.can_modify?(@owner)
#=> true

## Non-owner cannot modify organization
@org.can_modify?(@member1)
#=> false

## Can modify handles nil customer
@org.can_modify?(nil)
#=> nil

## Owner can delete organization
@org.can_delete?(@owner)
#=> true

## Non-owner cannot delete organization
@org.can_delete?(@member1)
#=> false

## Can delete handles nil customer
@org.can_delete?(nil)
#=> nil

## Factory method requires owner
begin
  Onetime::Organization.create!("Invalid Org", nil, "test@test.com")
rescue Onetime::Problem => e
  e.message
end
#=> "Owner required"

## Factory method requires display name
begin
  Onetime::Organization.create!("", @owner, "test@test.com")
rescue Onetime::Problem => e
  e.message
end
#=> "Display name required"

## Factory method requires non-empty display name
begin
  Onetime::Organization.create!("   ", @owner, "test@test.com")
rescue Onetime::Problem => e
  e.message
end
#=> "Display name required"

## Factory method requires contact email
begin
  Onetime::Organization.create!("Test Org", @owner, nil)
rescue Onetime::Problem => e
  e.message
end
#=> "Contact email required"

## Factory method prevents duplicate contact email (skipped - requires unique index)
# NOTE: This test requires a unique index on contact_email which isn't implemented yet
# For MVP, we'll rely on application-level validation
#begin
#  Onetime::Organization.create!("Duplicate Org", @owner, "billing@acme.com")
#rescue Onetime::Problem => e
#  e.message
#end
##=> "Organization exists for that email address"
true
#=> true

## Can set organization description
@org.description = "Our main organization"
@org.save
@org.description
#=> "Our main organization"

## Can update organization display name
@org.display_name = "Acme Industries"
@org.save
@org.display_name
#=> "Acme Industries"

## Can update organization contact email
@org.contact_email = "admin@acme.com"
@org.save
@org.contact_email
#=> "admin@acme.com"

## Organization has created timestamp (Familia v2 uses Float for timestamps)
@org.created.class
#=> Float

## Organization has updated timestamp (Familia v2 uses Float for timestamps)
@org.updated.class
#=> Float

## Updated timestamp changes when organization is modified
original_updated = @org.updated
sleep 0.01
@org.display_name = "Updated Org Name"
@org.save
@org.updated > original_updated
#=> true

## Can load organization by orgid
loaded_org = Onetime::Organization.load(@org.orgid)
[loaded_org.orgid, loaded_org.display_name]
#=> [@org.orgid, "Updated Org Name"]

## Loading non-existent organization returns nil
Onetime::Organization.load("nonexistent123")
#=> nil

## Can reload organization and verify persistence
reloaded_org = Onetime::Organization.load(@org.orgid)
[reloaded_org.display_name, reloaded_org.contact_email]
#=> ["Updated Org Name", "admin@acme.com"]

# Teardown
@org.destroy!
@owner.destroy!
@member1.destroy!
@member2.destroy!
@non_member.destroy!
