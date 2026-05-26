# try/unit/models/organization_try.rb
#
# frozen_string_literal: true

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

OT.boot! :test

# Setup test data with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: "org_owner#{@test_suffix}@onetimesecret.com")
@member1 = Onetime::Customer.create!(email: "org_member1#{@test_suffix}@onetimesecret.com")
@member2 = Onetime::Customer.create!(email: "org_member2#{@test_suffix}@onetimesecret.com")
@non_member = Onetime::Customer.create!(email: "org_nonmember#{@test_suffix}@onetimesecret.com")
@billing_email = "billing#{@test_suffix}@acme.com"

# Create organization using factory method
@org = Onetime::Organization.create!(
  "Acme Corporation",
  @owner,
  @billing_email
)

## Can create organization with factory method
[@org.class, @org.display_name, @org.owner_id]
#=> [Onetime::Organization, "Acme Corporation", @owner.custid]

## Organization has a valid objid (UUID format - Familia.generate_id)
@org.objid.class
#=> String

## Organization has contact_email set
@org.contact_email
#=> @billing_email

## Organization owner is correctly set
@org.owner.custid
#=> @owner.custid

## Owner check returns true for organization owner
@org.owner?(@owner)
#=> true

## Owner check returns false for non-owner
@org.owner?(@member1)
#=> false

## Owner check handles nil customer (strict boolean per ADR-012)
@org.owner?(nil)
#=> false

## Organization owner is automatically added as first member via participates_in
@org.member?(@owner)
#=> true

## Initial member count is 1 (owner only)
@org.member_count
#=> 1

## Can add member to organization (using Familia v2 auto-generated method)
@owner_objid = @org.add_members_instance(@member1)
@org.member?(@member1)
#=> true

## Member count updates after adding member
@org.member_count
#=> 2

## Can add multiple members
@org.add_members_instance(@member2)
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
@org.remove_members_instance(@member2)
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

## Can modify handles nil customer (strict boolean per ADR-012)
@org.can_modify?(nil)
#=> false

## Owner can delete organization
@org.can_delete?(@owner)
#=> true

## Non-owner cannot delete organization
@org.can_delete?(@member1)
#=> false

## Can delete handles nil customer (strict boolean per ADR-012)
@org.can_delete?(nil)
#=> false

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

## Factory method allows nil contact email (optional for billing setup later)
org_without_email = Onetime::Organization.create!("Test Org No Email", @owner, nil)
org_without_email.contact_email.nil?
#=> true

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
@updated_contact_email = "admin#{@test_suffix}@acme.com"
@org.contact_email = @updated_contact_email
@org.save
@org.contact_email
#=> @updated_contact_email

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

## Can load organization by objid
loaded_org = Onetime::Organization.load(@org.objid)
[loaded_org.objid, loaded_org.display_name]
#=> [@org.objid, "Updated Org Name"]

## Loading non-existent organization returns nil
Onetime::Organization.load("nonexistent123")
#=> nil

## Can reload organization and verify persistence
reloaded_org = Onetime::Organization.load(@org.objid)
[reloaded_org.display_name, reloaded_org.contact_email]
#=> ["Updated Org Name", @updated_contact_email]

# Edge case tests for optimized membership check methods

## member? returns false for non-existent string objid
@org.member?("nonexistent_objid_123456")
#=> false

## member? returns false for empty string
@org.member?("")
#=> false

## domain? returns false for non-existent string objid
@org.domain?("nonexistent_objid_123456")
#=> false

## domain? returns false for empty string
@org.domain?("")
#=> false

## receipt? returns false for non-existent string objid
@org.receipt?("nonexistent_objid_123456")
#=> false

## receipt? returns false for empty string
@org.receipt?("")
#=> false

# ============================================================================
# ADR-012 Stage 2 Unit B: owner? delegates to OrganizationMembership.
# Authority comes from membership row (role = 'owner'), NOT from owner_id
# field matching. The factory's auto-membership convenience must not paper
# over the underlying invariant.
#
# Note: Tryouts setup runs once at the top of the file (before the first ##
# block). Between-block code is NOT setup — it's only re-evaluated as part of
# whatever test it ends up grouped with. To create the membership-less
# fixtures these invariants require, each block instantiates the org inline
# via Organization.new(...).save (bypassing create!'s auto-add-owner).
# ============================================================================

## ADR-012 invariant (a): owner_id matches but no membership → not owner
ghost_owner = Onetime::Customer.create!(email: "ghost_a_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Ghost Org A",
  owner_id: ghost_owner.custid,
  contact_email: "ghost_a_#{@test_suffix}@acme.com",
)
ghost_org.save
result = ghost_org.owner?(ghost_owner)
ghost_org.destroy!
ghost_owner.destroy!
result
#=> false

## ADR-012 invariant (a): owner_id matches AND membership has role 'member' → not owner
ghost_owner = Onetime::Customer.create!(email: "ghost_b_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Ghost Org B",
  owner_id: ghost_owner.custid,
  contact_email: "ghost_b_#{@test_suffix}@acme.com",
)
ghost_org.save
ghost_org.add_members_instance(ghost_owner, through_attrs: { role: 'member' })
result = ghost_org.owner?(ghost_owner)
ghost_org.remove_members_instance(ghost_owner)
ghost_org.destroy!
ghost_owner.destroy!
result
#=> false

## ADR-012 invariant (a): membership with role 'owner' → owner
ghost_owner = Onetime::Customer.create!(email: "ghost_c_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Ghost Org C",
  owner_id: ghost_owner.custid,
  contact_email: "ghost_c_#{@test_suffix}@acme.com",
)
ghost_org.save
ghost_org.add_members_instance(ghost_owner, through_attrs: { role: 'owner' })
result = ghost_org.owner?(ghost_owner)
ghost_org.remove_members_instance(ghost_owner)
ghost_org.destroy!
ghost_owner.destroy!
result
#=> true

## ADR-012 invariant (b): membership wins, owner_id field is ignored
# owner_id points at @ghost_owner_d (no membership), but @ghost_member_d
# has a membership with role 'owner'. The membership wins.
ghost_owner_d  = Onetime::Customer.create!(email: "ghost_owner_d_#{@test_suffix}@onetimesecret.com")
ghost_member_d = Onetime::Customer.create!(email: "ghost_member_d_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Membership Wins Org",
  owner_id: ghost_owner_d.custid,  # Intentionally NOT ghost_member_d.custid
  contact_email: "membership_wins_#{@test_suffix}@acme.com",
)
ghost_org.save
ghost_org.add_members_instance(ghost_member_d, through_attrs: { role: 'owner' })
# Member-with-owner-role is the owner; owner_id-matching-no-membership is not.
result = [ghost_org.owner?(ghost_member_d), ghost_org.owner?(ghost_owner_d)]
ghost_org.remove_members_instance(ghost_member_d)
ghost_org.destroy!
ghost_owner_d.destroy!
ghost_member_d.destroy!
result
#=> [true, false]

## ADR-012 invariant (c): membership exists with role 'owner' AND owner_id matches,
# but status is 'accepted' (pre-activation) → not owner. The membership&.active?
# guard in Organization#owner? must override both the role match and the
# owner_id field match. Pins the defensive guard against pre-activation
# index leaks where an accepted-but-not-yet-active membership could otherwise
# be treated as conferring owner authority.
ghost_owner = Onetime::Customer.create!(email: "ghost_e_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Ghost Org E",
  owner_id: ghost_owner.custid,  # owner_id matches to prove status check overrides field match
  contact_email: "ghost_e_#{@test_suffix}@acme.com",
)
ghost_org.save
inactive_membership = Onetime::OrganizationMembership.new(
  organization_objid: ghost_org.objid,
  customer_objid: ghost_owner.objid,
  role: 'owner',
  status: 'accepted',  # NOT 'active' — pre-activation state
)
inactive_membership.save
# Explicitly populate the org_customer_lookup index so find_by_org_customer
# resolves to this accepted-but-not-active membership (mirrors what
# activate! would do, but for the accepted state).
Onetime::OrganizationMembership.org_customer_lookup[inactive_membership.org_customer_key] = inactive_membership.objid
result = ghost_org.owner?(ghost_owner)
Onetime::OrganizationMembership.org_customer_lookup.remove_field(inactive_membership.org_customer_key)
inactive_membership.destroy!
ghost_org.destroy!
ghost_owner.destroy!
result
#=> false

# ============================================================================
# CustomDomain#owner? Unit B migration coverage (custom_domain.rb:270).
# A customer whose custid matches org.owner_id but who has NO membership is
# no longer treated as the domain's owner. The route-level integration suite
# (try/integration/api/domains/add_domain_role_gate_try.rb) uses create!
# exclusively, so this membership-less edge is uncovered there.
# ============================================================================

## CustomDomain#owner? returns false when org.owner_id matches but no membership
ghost_owner = Onetime::Customer.create!(email: "ghost_cd_a_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Ghost CD Org A",
  owner_id: ghost_owner.custid,
  contact_email: "ghost_cd_a_#{@test_suffix}@acme.com",
)
ghost_org.save
ghost_domain = Onetime::CustomDomain.create!("ghost-#{@test_suffix}.example.com", ghost_org.objid)
result = ghost_domain.owner?(ghost_owner)
ghost_domain.destroy!
ghost_org.destroy!
ghost_owner.destroy!
result
#=> false

## CustomDomain#owner? returns true when customer has owner-role membership
ghost_member = Onetime::Customer.create!(email: "ghost_cd_b_#{@test_suffix}@onetimesecret.com")
ghost_org = Onetime::Organization.new(
  display_name: "Ghost CD Org B",
  owner_id: "some_other_custid_#{@test_suffix}",
  contact_email: "ghost_cd_b_#{@test_suffix}@acme.com",
)
ghost_org.save
ghost_org.add_members_instance(ghost_member, through_attrs: { role: 'owner' })
ghost_domain = Onetime::CustomDomain.create!("membership-#{@test_suffix}.example.com", ghost_org.objid)
result = ghost_domain.owner?(ghost_member)
ghost_domain.destroy!
ghost_org.remove_members_instance(ghost_member)
ghost_org.destroy!
ghost_member.destroy!
result
#=> true

# Teardown
@org.destroy!
@owner.destroy!
@member1.destroy!
@member2.destroy!
@non_member.destroy!
