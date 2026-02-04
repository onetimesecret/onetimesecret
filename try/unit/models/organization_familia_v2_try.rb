# try/unit/models/organization_familia_v2_try.rb
#
# frozen_string_literal: true

#
# Familia v2 relationship validation tests for Organization model
# Tests verify that auto-generated methods from participates_in work correctly
#
# CRITICAL: Organization should NOT manually define sorted_set :members
# Instead, this is AUTO-GENERATED:
# - members: by Customer.participates_in Organization, :members
#
# Auto-generated methods tested:
# - org.members (sorted_set) - auto-created by Customer participation
# - org.add_members_instance(customer) - auto-created
# - org.remove_members_instance(customer) - auto-created
# - customer.organization_instances - reverse lookup
# - customer.organization_ids - efficient ID-only access
# - customer.organization? - membership check
# - customer.organization_count - count without loading

require_relative '../../support/test_models'

OT.boot! :test

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: "org_owner_#{@test_suffix}@test.com")
@member = Onetime::Customer.create!(email: "org_member_#{@test_suffix}@test.com")
@billing_email = "billing_#{@test_suffix}@acme.com"

## Creating organization
@org = Onetime::Organization.create!("Acme Corp", @owner, @billing_email)
[@org.class, @org.display_name, @org.owner_id]
#=> [Onetime::Organization, "Acme Corp", @owner.custid]

## Owner automatically added as member
@org.member?(@owner)
#=> true

## Members collection auto-generated
@org.members.class
#=> Familia::SortedSet

## Members collection contains owner objid (using wrapper for Familia v2 serialization)
@org.member?(@owner.objid)
#=> true

## Owner helpers
[@org.owner.custid, @org.owner?(@owner), @org.can_modify?(@owner)]
#=> [@owner.custid, true, true]

## Non-owner cannot modify
@org.can_modify?(@member)
#=> false

## Adding members using auto-generated method
@org.add_members_instance(@member)
@org.member?(@member)
#=> true

## Members collection updated
@org.members.size
#=> 2

## Reverse relationship method exists (customer -> organizations)
@owner.respond_to?(:organization_instances)
#=> true

## Participations are tracked in Redis
@owner.participations.to_a.any? { |p| p.include?(@org.objid) }
#=> true

## Member participations tracked after adding
@member.participations.to_a.any? { |p| p.include?(@org.objid) }
#=> true

## List members with bulk loading
@members = @org.list_members
@members.size
#=> 2

## All members are Customer instances
@members.all? { |m| m.is_a?(Onetime::Customer) }
#=> true

## Members include owner and member
@members.map(&:custid).sort
#=> [@owner.custid, @member.custid].sort

## Removing members cleans forward side using auto-generated method
@org.remove_members_instance(@member)
@org.member?(@member)
#=> false

## Participations updated after removal
@member.participations.to_a.any? { |p| p.include?(@org.objid) }
#=> false

## Count decremented
@org.member_count
#=> 1

## Customer add_to_organization_members method works
@member.add_to_organization_members(@org, Familia.now.to_f)
@org.member?(@member)
#=> true

## Customer remove_from_organization_members method works
@member.remove_from_organization_members(@org)
@org.member?(@member)
#=> false

# Teardown
@org.destroy!
@owner.destroy!
@member.destroy!
