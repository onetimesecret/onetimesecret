# try/unit/models/organization_membership_cleanup_try.rb
#
# frozen_string_literal: true

#
# Unit tests for OrganizationMembership cleanup behavior
#
# DESIGN RATIONALE
# ================
# Familia's base destroy! method only deletes the object's Redis hash.
# It intentionally does NOT clean up application-level indexes because:
#
#   1. Familia is ORM-layer; indexes are application-layer concerns
#   2. Different operations need different cleanup:
#      - accept!  → removes from pending, adds to members, keeps record
#      - decline! → removes from pending, keeps record with 'declined' status
#      - revoke!  → removes from pending, destroys record and indexes
#   3. Follows ORM patterns where relationship cleanup is opt-in
#
# METHOD CONTRACT
# ===============
# - destroy! (Familia base)     : Deletes Redis hash only. NO index cleanup.
#                                 Use only when you explicitly want no cleanup.
#
# - destroy_with_index_cleanup! : Cleans up ALL indexes + pending set, then destroy!
#                                 Use for safe deletion in tests/migrations.
#
# - revoke!                     : Semantic method for admins revoking invitations.
#                                 Validates state, cleans up, destroys.
#
# - decline!                    : Semantic method for invitees declining.
#                                 Removes from pending but KEEPS the record.
#
# - accept!                     : Semantic method for invitees accepting.
#                                 Removes from pending, adds to members.
#
# WHY THIS MATTERS
# ================
# Stale objids in pending_invitations cause pending_invitation_count to return
# incorrect values, which breaks quota enforcement (users blocked from inviting
# when they're actually under limit).

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

# Teardown for basic decline! test
@invite_decline_record = Onetime::OrganizationMembership.load(@invite_decline_id)
@invite_decline_record&.destroy!

# --- Test decline! index cleanup behavior ---

## Create invitation for index cleanup test
@invite_idx = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "decline_idx_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@invite_idx_id = @invite_idx.objid
@invite_idx_token = @invite_idx.token
@invite_idx_email_key = @invite_idx.org_email_key
@invite_idx.pending?
#=> true

## Verify token_lookup exists before decline
Onetime::OrganizationMembership.find_by_token(@invite_idx_token).nil?
#=> false

## Verify org_email_lookup exists before decline
Onetime::OrganizationMembership.org_email_lookup[@invite_idx_email_key].nil?
#=> false

## decline! the invitation
@invite_idx.decline!
@invite_idx.status
#=> 'declined'

## After decline!: token_lookup entry is removed (can't find by old token)
Onetime::OrganizationMembership.find_by_token(@invite_idx_token)
#=> nil

## After decline!: org_email_lookup entry is removed
Onetime::OrganizationMembership.org_email_lookup[@invite_idx_email_key]
#=> nil

## After decline!: record still exists with status='declined'
@declined_record = Onetime::OrganizationMembership.load(@invite_idx_id)
[@declined_record.nil?, @declined_record&.status]
#=> [false, 'declined']

## After decline!: token is cleared on the record
@declined_record.token.nil?
#=> true

# Teardown for index cleanup test
@declined_record&.destroy!

# --- Test decline! allows re-invitation to same email ---

## Create invitation that will be declined
@reinvite_first = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "reinvite_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@reinvite_first_id = @reinvite_first.objid
@reinvite_first.pending?
#=> true

## Decline the first invitation
@reinvite_first.decline!
@reinvite_first.status
#=> 'declined'

## After decline, can create new invitation to same email (org_email_lookup cleared)
@reinvite_second = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "reinvite_test_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@reinvite_second.pending?
#=> true

## New invitation has different objid
@reinvite_second.objid != @reinvite_first_id
#=> true

## New invitation has its own token
@reinvite_second.token.nil?
#=> false

# Teardown for re-invitation test
Onetime::OrganizationMembership.load(@reinvite_first_id)&.destroy!
@reinvite_second&.destroy_with_index_cleanup!

# --- Test decline! edge cases ---

## Edge case: decline! with nil token does not crash
@nil_token_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "nil_token_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@nil_token_invite_id = @nil_token_invite.objid
# Manually clear token to simulate edge case (e.g., data migration scenario)
Onetime::OrganizationMembership.token_lookup.remove_field(@nil_token_invite.token)
@nil_token_invite.token = nil
@nil_token_invite.save
# Now decline - should not crash
@nil_token_result = begin
  @nil_token_invite.decline!
  'success'
rescue => e
  "error: #{e.class}"
end
@nil_token_result
#=> 'success'

## Edge case invitation has declined status after operation
@nil_token_check = Onetime::OrganizationMembership.load(@nil_token_invite_id)
@nil_token_check.status
#=> 'declined'

# Teardown for nil token edge case
@nil_token_check&.destroy!

## Edge case: decline! with nil org_email_key does not crash
@nil_email_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: "nil_email_key_#{@timestamp}@example.com",
  role: 'member',
  inviter: @owner
)
@nil_email_invite_id = @nil_email_invite.objid
@nil_email_invite_token = @nil_email_invite.token
# Manually clear invited_email to make org_email_key return nil
Onetime::OrganizationMembership.org_email_lookup.remove_field(@nil_email_invite.org_email_key)
@nil_email_invite.invited_email = nil
@nil_email_invite.save
# Verify org_email_key is now nil
@nil_email_invite.org_email_key.nil?
#=> true

## decline! with nil org_email_key does not crash
@nil_email_result = begin
  @nil_email_invite.decline!
  'success'
rescue => e
  "error: #{e.class}"
end
@nil_email_result
#=> 'success'

## Edge case invitation has declined status
@nil_email_check = Onetime::OrganizationMembership.load(@nil_email_invite_id)
@nil_email_check.status
#=> 'declined'

# Teardown for nil email key edge case
Onetime::OrganizationMembership.token_lookup.remove_field(@nil_email_invite_token) rescue nil
@nil_email_check&.destroy!

# Teardown

@org&.destroy!
@owner&.destroy!
