# try/unit/models/organization_membership_removal_try.rb
#
# frozen_string_literal: true

#
# Tests member removal and invitation revocation codepaths, verifying that
# all Redis indexes are properly cleaned up.
#
# Issue #2906 consolidates removal to avoid a double-destroy pattern.
# The two primary removal paths are:
#
#   1. Active member removal (RemoveMember API logic):
#      - org.remove_members_instance(customer)  -- Familia sorted set + reverse index
#      - membership.destroy_with_index_cleanup!  -- OTS indexes + model hash
#
#   2. Pending invitation revocation (revoke!):
#      - Cleans OTS indexes (token_lookup, org_email_lookup, org_customer_lookup)
#      - org.unstage_members_instance(staged)    -- staging set + model hash
#
# Both paths must leave zero stale references in:
#   - org.members sorted set
#   - org.pending_invitations staging set
#   - token_lookup hash
#   - org_email_lookup hash
#   - org_customer_lookup hash
#   - customer reverse index (organization_instances)

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("removal_owner"))
@org = Onetime::Organization.create!("Removal Test Org", @owner, generate_unique_test_email("removal_contact"))

# ============================================================================
# Active member removal via destroy_with_index_cleanup!
# ============================================================================

## Setup: add a member directly and verify baseline
@member = Onetime::Customer.create!(email: generate_unique_test_email("removal_member"))
@membership = Onetime::OrganizationMembership.ensure_membership(@org, @member)
@org.member?(@member)
#=> true

## Baseline: member count includes owner + member
@org.member_count
#=> 2

## Baseline: org_customer_lookup is populated for the member
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @member.objid).nil?
#=> false

## Baseline: org_email_lookup is NOT populated for direct-add members (no invited_email)
# org_email_lookup only applies to memberships created via the invitation flow
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @member.email)
#=> nil

## Baseline: reverse index populated (member sees the org)
@member.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Remove active member: remove from sorted set first, then destroy membership
@org.remove_members_instance(@member)
@membership.destroy_with_index_cleanup!
@org.member?(@member)
#=> false

## After removal: member count decremented back to 1 (owner only)
@org.member_count
#=> 1

## After removal: org_customer_lookup is nil
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @member.objid)
#=> nil

## After removal: org_email_lookup remains nil (was never set for direct-add)
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @member.email)
#=> nil

## After removal: membership model is destroyed
Onetime::OrganizationMembership.load(@membership.objid)
#=> nil

## After removal: reverse index cleaned (Familia remove_members_instance handles this)
@member.organization_instances.any? { |o| o.objid == @org.objid }
#=> false

# ============================================================================
# Pending invitation revocation via revoke!
# ============================================================================

## Create a pending invitation
@pending_email = generate_unique_test_email("removal_pending")
@pending = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @pending_email,
  role: 'member',
  inviter: @owner
)
@pending_token = @pending.token
@pending_objid = @pending.objid
@pending.pending?
#=> true

## Pending invitation is in the staging set
@org.pending_invitations.member?(@pending_objid)
#=> true

## Pending: token_lookup is populated
Onetime::OrganizationMembership.find_by_token(@pending_token).nil?
#=> false

## Pending: org_email_lookup is populated
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @pending_email).nil?
#=> false

## Revoke the pending invitation
@pending.revoke!
#=> true

## After revoke: token_lookup is nil
Onetime::OrganizationMembership.find_by_token(@pending_token)
#=> nil

## After revoke: org_email_lookup is nil
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @pending_email)
#=> nil

## After revoke: model is destroyed
Onetime::OrganizationMembership.load(@pending_objid)
#=> nil

## After revoke: staging set no longer contains the invitation
@org.pending_invitations.member?(@pending_objid)
#=> false

## After revoke: pending invitation count is 0
@org.pending_invitation_count
#=> 0

# ============================================================================
# Index cleanup completeness -- all lookup paths return nil
# ============================================================================

## Add and remove a member with invitation history to verify full cleanup
@full_cleanup_customer = Onetime::Customer.create!(email: generate_unique_test_email("removal_full"))
@full_cleanup_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @full_cleanup_customer.email,
  role: 'admin',
  inviter: @owner
)
@full_cleanup_token = @full_cleanup_invite.token
@full_cleanup_invite.accept!(@full_cleanup_customer)
@full_cleanup_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @full_cleanup_customer.objid)
@full_cleanup_membership.active?
#=> true

## Full cleanup: remove the now-active member
@org.remove_members_instance(@full_cleanup_customer)
@full_cleanup_membership.destroy_with_index_cleanup!
true
#=> true

## Full cleanup: org_customer_lookup is nil
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @full_cleanup_customer.objid)
#=> nil

## Full cleanup: org_email_lookup is nil
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @full_cleanup_customer.email)
#=> nil

## Full cleanup: token_lookup for the original invite token is still nil (cleared during accept)
Onetime::OrganizationMembership.find_by_token(@full_cleanup_token)
#=> nil

## Full cleanup: model is destroyed
Onetime::OrganizationMembership.load(@full_cleanup_membership.objid)
#=> nil

## Full cleanup: not in org.members
@org.member?(@full_cleanup_customer)
#=> false

## Full cleanup: reverse index is clean
@full_cleanup_customer.organization_instances.any? { |o| o.objid == @org.objid }
#=> false

# ============================================================================
# Idempotent removal -- removing an already-removed member does not crash
# ============================================================================

## Setup: add a member and remove them
@idempotent_customer = Onetime::Customer.create!(email: generate_unique_test_email("removal_idempotent"))
@idempotent_ms = Onetime::OrganizationMembership.ensure_membership(@org, @idempotent_customer)
@idempotent_objid = @idempotent_ms.objid
@org.remove_members_instance(@idempotent_customer)
@idempotent_ms.destroy_with_index_cleanup!
@org.member?(@idempotent_customer)
#=> false

## Idempotent: calling remove_members_instance again does not raise
@org.remove_members_instance(@idempotent_customer)
true
#=> true

## Idempotent: calling destroy_with_index_cleanup! on destroyed membership does not raise
@idempotent_ms.destroy_with_index_cleanup!
true
#=> true

## Idempotent: lookups still return nil after double removal
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @idempotent_customer.objid)
#=> nil

# ============================================================================
# Re-invitation after removal -- same email can be re-invited
# ============================================================================

## Setup: create member, remove completely, then re-invite
@reinvite_customer = Onetime::Customer.create!(email: generate_unique_test_email("removal_reinvite"))
@reinvite_ms = Onetime::OrganizationMembership.ensure_membership(@org, @reinvite_customer)
@org.remove_members_instance(@reinvite_customer)
@reinvite_ms.destroy_with_index_cleanup!
@org.member?(@reinvite_customer)
#=> false

## Re-invite: create_invitation! succeeds for the same email after removal
@reinvitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @reinvite_customer.email,
  role: 'admin',
  inviter: @owner
)
@reinvitation.pending?
#=> true

## Re-invite: token_lookup is populated for the new invitation
Onetime::OrganizationMembership.find_by_token(@reinvitation.token).nil?
#=> false

## Re-invite: org_email_lookup points to the new invitation
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @reinvite_customer.email).objid == @reinvitation.objid
#=> true

## Re-invite: accepting the re-invitation works
@reinvitation.accept!(@reinvite_customer)
@reinvitation.active?
#=> true

## Re-invite: member is back in the org
@org.member?(@reinvite_customer)
#=> true

## Re-invite: org_customer_lookup is populated again
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @reinvite_customer.objid).nil?
#=> false

## Re-invite: reverse index is populated again
@reinvite_customer.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

# ============================================================================
# Member count accuracy through add/remove cycle
# ============================================================================

## Count baseline: org has owner + reinvited member = 2
@org.member_count
#=> 2

## Count: add two more members
@count_member_a = Onetime::Customer.create!(email: generate_unique_test_email("removal_count_a"))
@count_member_b = Onetime::Customer.create!(email: generate_unique_test_email("removal_count_b"))
@count_ms_a = Onetime::OrganizationMembership.ensure_membership(@org, @count_member_a)
@count_ms_b = Onetime::OrganizationMembership.ensure_membership(@org, @count_member_b)
@org.member_count
#=> 4

## Count: remove one member
@org.remove_members_instance(@count_member_a)
@count_ms_a.destroy_with_index_cleanup!
@org.member_count
#=> 3

## Count: remove another member
@org.remove_members_instance(@count_member_b)
@count_ms_b.destroy_with_index_cleanup!
@org.member_count
#=> 2

## Count: pending invitations do not affect member count
@count_pending = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: generate_unique_test_email("removal_count_pending"),
  role: 'member',
  inviter: @owner
)
@org.member_count
#=> 2

## Count: pending invitation count is separate
@org.pending_invitation_count
#=> 1

# Cleanup
@count_pending.destroy_with_index_cleanup! if @count_pending&.respond_to?(:destroy!)
# Clean up reinvited member's active membership
@reinvite_active = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @reinvite_customer.objid)
if @reinvite_active
  @org.remove_members_instance(@reinvite_customer)
  @reinvite_active.destroy_with_index_cleanup!
end
[@org, @owner, @member, @full_cleanup_customer, @idempotent_customer, @reinvite_customer, @count_member_a, @count_member_b].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
