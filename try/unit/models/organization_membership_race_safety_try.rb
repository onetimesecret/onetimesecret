# try/unit/models/organization_membership_race_safety_try.rb
#
# frozen_string_literal: true

#
# Tests race condition safety and domain scope lookup in OrganizationMembership.
#
# Issue 1: ensure_membership must be idempotent even when called concurrently.
#   - Calling ensure_membership twice with the same args returns the same membership.
#   - accept! returns true (no raise) when the customer is already an active member.
#   - The rescue in ensure_membership catches Familia::Problem from mid-flight activation.
#
# Issue 2: find_all_by_domain_scope returns memberships scoped to a specific domain.
#   - Returns only domain-scoped memberships matching the given domain objid.
#   - Returns empty array for nil/empty domain objid.
#   - Does not return org-scoped memberships.
#   - Filters correctly when multiple domains have scoped memberships.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("race_owner"))
@org = Onetime::Organization.create!("Race Safety Test Org", @owner, generate_unique_test_email("race_contact"))

@domain_a_objid = "cust_domain_#{SecureRandom.hex(8)}"
@domain_b_objid = "cust_domain_#{SecureRandom.hex(8)}"


# =============================================================================
# ensure_membership idempotency tests
# =============================================================================

## ensure_membership called twice returns same membership objid
@idem_customer = Onetime::Customer.create!(email: generate_unique_test_email("race_idem"))
@first = Onetime::OrganizationMembership.ensure_membership(@org, @idem_customer, domain_scope_id: @domain_a_objid)
@second = Onetime::OrganizationMembership.ensure_membership(@org, @idem_customer, domain_scope_id: @domain_a_objid)
@first.objid == @second.objid
#=> true

## ensure_membership idempotent: member count unchanged after second call
@count_before = @org.member_count
Onetime::OrganizationMembership.ensure_membership(@org, @idem_customer, domain_scope_id: @domain_a_objid)
@org.member_count == @count_before
#=> true

## ensure_membership idempotent: domain_scope_id unchanged on re-call
@second.domain_scope_id
#=> @domain_a_objid

## ensure_membership idempotent: re-call with different domain_scope_id still returns original scope
@third = Onetime::OrganizationMembership.ensure_membership(@org, @idem_customer, domain_scope_id: @domain_b_objid)
@third.domain_scope_id
#=> @domain_a_objid


# =============================================================================
# accept! idempotency tests
# =============================================================================

## accept! returns true when invitation is already active (no raise)
@accept_customer = Onetime::Customer.create!(email: generate_unique_test_email("race_accept"))
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @accept_customer.email,
  role: 'member',
  inviter: @owner
)
@invitation.accept!(@accept_customer)
@result_first = @invitation.accept!(@accept_customer)
@result_first
#=> true

## accept! on already-active invitation does not raise
@no_error = begin
  @invitation.accept!(@accept_customer)
  true
rescue => e
  e.message
end
@no_error
#=> true

## accept! idempotency: customer still a member after double accept
@org.member?(@accept_customer)
#=> true


# =============================================================================
# accept! when customer was concurrently added via add_members_instance
# =============================================================================

## accept! returns true when customer is already org member via different path
@concurrent_customer = Onetime::Customer.create!(email: generate_unique_test_email("race_concurrent"))
@concurrent_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @concurrent_customer.email,
  role: 'member',
  inviter: @owner
)
# Simulate concurrent add_members_instance (as if another process added the customer)
@org.add_members_instance(@concurrent_customer, through_attrs: { role: 'member', status: 'active', joined_at: Familia.now.to_f })
# Now accept! should detect member already exists and return gracefully
@concurrent_result = @concurrent_invite.accept!(@concurrent_customer)
@concurrent_result
#=> true


# =============================================================================
# find_all_by_domain_scope tests
# =============================================================================

## find_all_by_domain_scope returns empty array for nil domain_objid
Onetime::OrganizationMembership.find_all_by_domain_scope(nil)
#=> []

## find_all_by_domain_scope returns empty array for empty string domain_objid
Onetime::OrganizationMembership.find_all_by_domain_scope('')
#=> []

## find_all_by_domain_scope returns memberships scoped to domain A
@ds_cust1 = Onetime::Customer.create!(email: generate_unique_test_email("race_ds1"))
@ds_cust2 = Onetime::Customer.create!(email: generate_unique_test_email("race_ds2"))
Onetime::OrganizationMembership.ensure_membership(@org, @ds_cust1, domain_scope_id: @domain_a_objid)
Onetime::OrganizationMembership.ensure_membership(@org, @ds_cust2, domain_scope_id: @domain_a_objid)
@domain_a_members = Onetime::OrganizationMembership.find_all_by_domain_scope(@domain_a_objid, organization: @org)
@domain_a_members.length
#=> 3

## find_all_by_domain_scope results are all domain-scoped to domain A
@domain_a_members.all? { |m| m.domain_scope_id == @domain_a_objid }
#=> true

## find_all_by_domain_scope returns memberships scoped to domain B
@ds_cust3 = Onetime::Customer.create!(email: generate_unique_test_email("race_ds3"))
Onetime::OrganizationMembership.ensure_membership(@org, @ds_cust3, domain_scope_id: @domain_b_objid)
@domain_b_members = Onetime::OrganizationMembership.find_all_by_domain_scope(@domain_b_objid, organization: @org)
@domain_b_members.length
#=> 1

## find_all_by_domain_scope does not return org-scoped memberships
@orgscoped_cust = Onetime::Customer.create!(email: generate_unique_test_email("race_orgscoped"))
Onetime::OrganizationMembership.ensure_membership(@org, @orgscoped_cust)
@domain_a_after = Onetime::OrganizationMembership.find_all_by_domain_scope(@domain_a_objid, organization: @org)
@domain_a_after.none? { |m| m.org_scoped? }
#=> true

## find_all_by_domain_scope for nonexistent domain returns empty array
@nonexistent = Onetime::OrganizationMembership.find_all_by_domain_scope("cust_domain_nonexistent", organization: @org)
@nonexistent
#=> []


# Cleanup
[@org, @owner, @idem_customer, @accept_customer, @concurrent_customer, @ds_cust1, @ds_cust2, @ds_cust3, @orgscoped_cust].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
