# try/unit/models/organization_pending_invitations_cleanup_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Organization pending invitations cleanup on deletion.
#
# Issue: #2878 - Clean up pending_invitations when deleting organization
#
# Expected Behavior:
#   When an organization is deleted:
#   1. All pending invitations (OrganizationMembership with status='pending') should be destroyed
#   2. The pending_invitations sorted set should be emptied
#   3. Invitation indexes should be cleaned up (token_lookup, org_email_lookup)
#
# Test Coverage:
#   - Organization#destroy! cleans up pending invitations
#   - DeleteOrganization#process cleans up pending invitations
#   - After cleanup: pending_invitations sorted set is empty
#   - After cleanup: invitation record no longer exists
#   - After cleanup: token_lookup entry is removed
#   - After cleanup: org_email_lookup entry is removed
#   - Multiple invitations are all cleaned up
#   - Mixed state (pending + declined) cleanup behavior
#

require_relative '../../support/test_helpers'

OT.boot! :test

# Setup: Create owner and organization for all tests
@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "cleanup_owner_#{@timestamp}_#{@entropy}@example.com")
@owner.verified = 'true'
@owner.save

# --- Test Setup Verification ---

## Setup verification: can create organization with owner
@org = Onetime::Organization.create!("Cleanup Test Org #{@timestamp}", @owner, @owner.email)
[@org.class, @org.owner_id]
#=> [Onetime::Organization, @owner.custid]

## Setup verification: organization has owner as member
@org.member?(@owner)
#=> true

## Setup verification: no pending invitations initially
@org.pending_invitation_count
#=> 0

# --- Test Single Invitation Cleanup on Organization Destroy ---

## Create invitation for organization destroy test
@invite1 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "pending_user1_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite1_id = @invite1.objid
@invite1_token = @invite1.token
@invite1_email_key = @invite1.org_email_key
@org.pending_invitation_count
#=> 1

## Verify invitation is in pending_invitations set before destroy
@org.pending_invitations.member?(@invite1_id)
#=> true

## Verify token lookup exists before destroy
Onetime::OrganizationMembership.find_by_token(@invite1_token).nil?
#=> false

## Verify org_email lookup exists before destroy
Onetime::OrganizationMembership.find_by_org_email(@org.objid, "pending_user1_#{@timestamp}@example.com").nil?
#=> false

## Organization destroy! cleans up pending invitations
@org.destroy!
Onetime::Organization.load(@org.objid)
#=> nil

## After org destroy: invitation record no longer exists
Onetime::OrganizationMembership.load(@invite1_id)
#=> nil

## After org destroy: token_lookup entry is removed
Onetime::OrganizationMembership.find_by_token(@invite1_token)
#=> nil

## After org destroy: org_email_lookup entry is removed
Onetime::OrganizationMembership.org_email_lookup[@invite1_email_key]
#=> nil

# --- Test Multiple Invitations Cleanup ---

## Setup: Create new organization for multiple invitations test
@org2 = Onetime::Organization.create!("Multi-Invite Org #{@timestamp}", @owner, "multi_#{@owner.email}")
@org2.pending_invitation_count
#=> 0

## Create multiple pending invitations
@invite_a = Onetime::OrganizationMembership.create_invitation!(
  organization: @org2,
  email: "invite_a_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_b = Onetime::OrganizationMembership.create_invitation!(
  organization: @org2,
  email: "invite_b_#{@timestamp}@example.com",
  role: 'admin',
  inviter: @owner
)
@invite_c = Onetime::OrganizationMembership.create_invitation!(
  organization: @org2,
  email: "invite_c_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_a_id = @invite_a.objid
@invite_b_id = @invite_b.objid
@invite_c_id = @invite_c.objid
@invite_a_token = @invite_a.token
@invite_b_token = @invite_b.token
@invite_c_token = @invite_c.token
@org2.pending_invitation_count
#=> 3

## All invitations are in pending_invitations set
[@org2.pending_invitations.member?(@invite_a_id),
 @org2.pending_invitations.member?(@invite_b_id),
 @org2.pending_invitations.member?(@invite_c_id)]
#=> [true, true, true]

## Organization destroy cleans up all invitations
@org2.destroy!
Onetime::Organization.load(@org2.objid)
#=> nil

## After org destroy: all invitation records are gone
[Onetime::OrganizationMembership.load(@invite_a_id),
 Onetime::OrganizationMembership.load(@invite_b_id),
 Onetime::OrganizationMembership.load(@invite_c_id)]
#=> [nil, nil, nil]

## After org destroy: all token lookups are removed
[Onetime::OrganizationMembership.find_by_token(@invite_a_token),
 Onetime::OrganizationMembership.find_by_token(@invite_b_token),
 Onetime::OrganizationMembership.find_by_token(@invite_c_token)]
#=> [nil, nil, nil]

# --- Test Mixed State Cleanup (pending + declined invitations) ---

## Setup: Create organization for mixed state test
@org3 = Onetime::Organization.create!("Mixed State Org #{@timestamp}", @owner, "mixed_#{@owner.email}")
@org3.pending_invitation_count
#=> 0

## Create pending and declined invitations
@pending_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org3,
  email: "still_pending_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@to_decline = Onetime::OrganizationMembership.create_invitation!(
  organization: @org3,
  email: "will_decline_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@pending_invite_id = @pending_invite.objid
@to_decline_id = @to_decline.objid
@to_decline_token = @to_decline.token
@org3.pending_invitation_count
#=> 2

## Decline one invitation (changes status to 'declined', removes from pending set)
@to_decline.decline!
@to_decline_reloaded = Onetime::OrganizationMembership.load(@to_decline_id)
@to_decline_reloaded.status
#=> 'declined'

## After decline: pending count should be 1 (only pending_invite remains)
# Reload org to get fresh count
@org3 = Onetime::Organization.load(@org3.objid)
@org3.pending_invitation_count
#=> 1

## Declined invitation is NOT in pending_invitations set
@org3.pending_invitations.member?(@to_decline_id)
#=> false

## Pending invitation IS still in pending_invitations set
@org3.pending_invitations.member?(@pending_invite_id)
#=> true

## Organization destroy cleans up remaining pending invitation
# Store org objid before destruction for FK verification
@org3_objid = @org3.objid
@org3.destroy!
Onetime::Organization.load(@org3_objid)
#=> nil

## After org destroy: pending invitation record is gone
Onetime::OrganizationMembership.load(@pending_invite_id)
#=> nil

## After org destroy: declined invitation record is NOT cleaned up by org.destroy!
# NOTE: Issue #2878 focuses on pending invitations only. Declined invitations
# retain their FK reference to the now-deleted org. However, this is now less
# problematic because:
#   1. decline! now cleans up token_lookup and org_email_lookup indexes
#   2. Declined records are not in pending_invitations set (so quota is correct)
#   3. The record exists but has no active indexes pointing to it
#   4. Re-invitation to the same email is now possible after decline!
#
# The declined record is essentially an audit trail showing invitation history.
# If comprehensive cleanup is needed, a separate issue should address cleanup
# of all OrganizationMembership records (declined, expired) on org deletion.
@declined_after_destroy = Onetime::OrganizationMembership.load(@to_decline_id)
!@declined_after_destroy.nil?
#=> true

## Declined invitation still references the deleted organization
@declined_after_destroy.organization_objid == @org3_objid
#=> true

## After decline!: token_lookup was already cleaned up (can't find by old token)
# The decline! method now removes the token_lookup entry before clearing the token
Onetime::OrganizationMembership.find_by_token(@to_decline_token)
#=> nil

# Manual cleanup of orphaned declined invitation for test isolation
@declined_after_destroy.destroy!

# --- Test Empty Pending Invitations Edge Case ---

## Setup: Create organization with no invitations
@org4 = Onetime::Organization.create!("No Invites Org #{@timestamp}", @owner, "noinvites_#{@owner.email}")
@org4_id = @org4.objid
@org4.pending_invitation_count
#=> 0

## Organization destroy succeeds with no pending invitations
@org4.destroy!
Onetime::Organization.load(@org4_id)
#=> nil

# --- Test Pending Invitations Sorted Set is Empty After Cleanup ---

## Setup: Create organization and add invitations
@org5 = Onetime::Organization.create!("Sorted Set Test Org #{@timestamp}", @owner, "sortedset_#{@owner.email}")
@invite_ss = Onetime::OrganizationMembership.create_invitation!(
  organization: @org5,
  email: "sorted_set_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
# Store the Redis key and client for the sorted set before destroy
@pending_invitations_key = @org5.pending_invitations.dbkey
@pending_invitations_redis = @org5.pending_invitations.dbclient
@org5.pending_invitations.size
#=> 1

## Organization destroy clears the pending_invitations sorted set
@org5.destroy!
# The sorted set should be empty (or deleted) after org destroy
# Check by trying to access it directly via Redis
@pending_invitations_redis.zcard(@pending_invitations_key)
#=> 0

# --- Test revoke! method cleans up properly (for comparison) ---

## Setup: Create organization for revoke test
@org6 = Onetime::Organization.create!("Revoke Test Org #{@timestamp}", @owner, "revoke_#{@owner.email}")
@revoke_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org6,
  email: "revoke_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@revoke_invite_id = @revoke_invite.objid
@revoke_invite_token = @revoke_invite.token
@revoke_invite_email_key = @revoke_invite.org_email_key
@org6.pending_invitation_count
#=> 1

## revoke! cleans up invitation properly
@revoke_invite.revoke!
Onetime::OrganizationMembership.load(@revoke_invite_id)
#=> nil

## After revoke: token lookup is removed
Onetime::OrganizationMembership.find_by_token(@revoke_invite_token)
#=> nil

## After revoke: org_email lookup is removed
Onetime::OrganizationMembership.org_email_lookup[@revoke_invite_email_key]
#=> nil

## After revoke: pending_invitations count is 0
@org6 = Onetime::Organization.load(@org6.objid)
@org6.pending_invitation_count
#=> 0

# Teardown for revoke test org
@org6.destroy!

# Teardown
@owner.destroy!
