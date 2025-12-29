# try/unit/models/organization_membership_through_try.rb
#
# frozen_string_literal: true

#
# Tests for OrganizationMembership as a through model for Customer/Organization
#
# The :through option on participates_in auto-creates/destroys OrganizationMembership
# models when adding/removing members from organizations.
#
# Key behaviors tested:
# - Through model auto-created on add_members_instance
# - through_attrs passed to through model
# - Through model returned for chaining
# - Through model destroyed on remove_members_instance
# - Idempotent: re-adding updates existing
# - Backward compat maintained for existing orgs

require_relative '../../support/test_models'

OT.boot! :test

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: "through_owner_#{@test_suffix}@test.com")
@member = Onetime::Customer.create!(email: "through_member_#{@test_suffix}@test.com")
@billing_email = "through_billing_#{@test_suffix}@acme.com"

## Customer has participates_in with through option
@rel = Onetime::Customer.participation_relationships.find { |r| r.collection_name == :members && r.target_class == Onetime::Organization }
@rel.through
#=> Onetime::OrganizationMembership

## Organization created with owner
@org = Onetime::Organization.create!("Through Test Org", @owner, @billing_email)
@org.class
#=> Onetime::Organization

## Owner added as member (tests through model creation)
@org.member?(@owner)
#=> true

## Through model created for owner
@owner_key = "organization:#{@org.objid}:customer:#{@owner.objid}:organization_membership"
@owner_membership = Onetime::OrganizationMembership.load(@owner_key)
@owner_membership.nil? || !@owner_membership.exists? ? false : true
#=> true

## Through model has organization_objid
@owner_membership.organization_objid
#=> @org.objid

## Through model has customer_objid
@owner_membership.customer_objid
#=> @owner.objid

## Through model has owner role (set via through_attrs in Organization.create!)
@owner_membership.role
#=> 'owner'

## Through model has default status
@owner_membership.status
#=> 'active'

## Through model has updated_at set
@owner_membership.updated_at.is_a?(Float)
#=> true

## Adding member with through_attrs
@result = @org.add_members_instance(@member, through_attrs: { role: 'admin' })
@result.class
#=> Onetime::OrganizationMembership

## Member added to org
@org.member?(@member)
#=> true

## Through model for member created with role
@member_key = "organization:#{@org.objid}:customer:#{@member.objid}:organization_membership"
@member_membership = Onetime::OrganizationMembership.load(@member_key)
@member_membership.role
#=> 'admin'

## Returned through model supports chaining
@result.respond_to?(:role=)
#=> true

## Returned through model has correct role
@result.role
#=> 'admin'

## Updating through model via chaining
@result.role = 'owner'
@result.save
@reloaded = Onetime::OrganizationMembership.load(@member_key)
@reloaded.role
#=> 'owner'

## Idempotent: re-adding updates existing
@old_objid = @member_membership.objid
@updated = @org.add_members_instance(@member, through_attrs: { role: 'member' })
@updated.objid == @old_objid
#=> true

## Role updated by re-add
@check = Onetime::OrganizationMembership.load(@member_key)
@check.role
#=> 'member'

## Removing member destroys through model
@org.remove_members_instance(@member)
@org.member?(@member)
#=> false

## Through model destroyed
@removed = Onetime::OrganizationMembership.load(@member_key)
@removed.nil? || !@removed.exists? ? true : false
#=> true

## Owner membership still exists
@owner_still = Onetime::OrganizationMembership.load(@owner_key)
@owner_still.exists?
#=> true

## OrganizationMembership helper methods work
@owner_still.active?
#=> true

## OrganizationMembership organization lookup
@owner_still.organization.objid == @org.objid
#=> true

## OrganizationMembership customer lookup
@owner_still.customer.objid == @owner.objid
#=> true

# Cleanup
[@org, @owner, @member].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
