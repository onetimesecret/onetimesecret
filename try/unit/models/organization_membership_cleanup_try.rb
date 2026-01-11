# try/unit/models/organization_membership_cleanup_try.rb
#
# frozen_string_literal: true

#
# Unit tests for OrganizationMembership cleanup behavior
#
# Documents the contract for different destroy/cleanup methods:
# - destroy! (Familia base): deletes record only, does NOT clean up pending set
# - destroy_with_index_cleanup!: cleans up indexes AND pending set
# - revoke!: semantic method for revoking pending invitations (uses destroy_with_index_cleanup!)
#
# This distinction is important because stale objids in pending_invitations
# cause incorrect quota calculations.

require_relative '../../support/test_helpers'

OT.boot! :test

# Setup: Create owner and organization
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "cleanup_test_owner_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

@org = Onetime::Organization.create!("Cleanup Test Org", @owner, @owner.email)

## Setup verification: organization exists with owner
@org.member_count
#=> 1

## Setup verification: no pending invitations initially
@org.pending_invitation_count
#=> 0

# --- Test destroy! behavior (Familia base method) ---

## Create invitation for destroy! test
@invite_destroy = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "destroy_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_destroy_id = @invite_destroy.objid
@org.pending_invitation_count
#=> 1

## destroy! deletes the record
@invite_destroy.destroy!
Onetime::OrganizationMembership.load(@invite_destroy_id)
#=> nil

## IMPORTANT: destroy! does NOT remove from pending_invitations set
# This is expected behavior - destroy! is low-level and doesn't know about pending set
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitations.member?(@invite_destroy_id)
#=> true

## pending_invitation_count is now stale (shows 1, but record is gone)
@org.pending_invitation_count
#=> 1

## Manual cleanup for next test
@org.pending_invitations.remove(@invite_destroy_id)
@org.pending_invitation_count
#=> 0

# --- Test destroy_with_index_cleanup! behavior ---

## Create invitation for destroy_with_index_cleanup! test
@invite_cleanup = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "cleanup_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_cleanup_id = @invite_cleanup.objid
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitation_count
#=> 1

## destroy_with_index_cleanup! deletes the record
@invite_cleanup.destroy_with_index_cleanup!
Onetime::OrganizationMembership.load(@invite_cleanup_id)
#=> nil

## destroy_with_index_cleanup! DOES remove from pending_invitations set
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitations.member?(@invite_cleanup_id)
#=> false

## pending_invitation_count is accurate after destroy_with_index_cleanup!
@org.pending_invitation_count
#=> 0

# --- Test revoke! behavior ---

## Create invitation for revoke! test
@invite_revoke = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "revoke_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_revoke_id = @invite_revoke.objid
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitation_count
#=> 1

## revoke! deletes the record (delegates to destroy_with_index_cleanup!)
@invite_revoke.revoke!
Onetime::OrganizationMembership.load(@invite_revoke_id)
#=> nil

## revoke! DOES remove from pending_invitations set
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitations.member?(@invite_revoke_id)
#=> false

## pending_invitation_count is accurate after revoke!
@org.pending_invitation_count
#=> 0

# --- Test decline! behavior ---

## Create invitation for decline! test
@invite_decline = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "decline_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_decline_id = @invite_decline.objid
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitation_count
#=> 1

## decline! keeps the record but changes status
@invite_decline.decline!
declined = Onetime::OrganizationMembership.load(@invite_decline_id)
declined.status
#=> 'declined'

## decline! DOES remove from pending_invitations set
@org = Onetime::Organization.load(@org.objid)
@org.pending_invitations.member?(@invite_decline_id)
#=> false

## pending_invitation_count is accurate after decline!
@org.pending_invitation_count
#=> 0

# Teardown
# Clean up declined invitation (still exists with 'declined' status)
@invite_decline_record = Onetime::OrganizationMembership.load(@invite_decline_id)
@invite_decline_record&.destroy!

@org&.destroy!
@owner&.destroy!
