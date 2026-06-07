# try/unit/models/organization_membership_index_lifecycle_try.rb
#
# frozen_string_literal: true

#
# Tests OTS-specific index transitions during the staged relationship lifecycle.
#
# The invitation flow moves through three phases (staged -> active or revoked),
# and each phase has different index expectations:
#
#   STAGED (pending invitation):
#     - token_lookup: populated (enables find_by_token for accept links)
#     - find_pending_by_email: discoverable via staged set scan
#
#   ACTIVE (accepted invitation):
#     - token_lookup: removed (token cleared for security)
#     - find_pending_by_email: no longer discoverable (status is active)
#     - find_by_org_customer: discoverable via direct composite key load
#
#   REVOKED (via unstage):
#     - token_lookup: removed
#     - find_pending_by_email: no longer discoverable (model destroyed)
#     - model destroyed
#
# This complements organization_membership_accept_participation_try.rb which
# tests the three-structure invariant (members set, reverse index, staging set).
# Here we verify the OTS application-level indexes are correctly managed.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("idx_lifecycle_owner"))
@org = Onetime::Organization.create!("Index Lifecycle Test Org", @owner, generate_unique_test_email("idx_lifecycle_contact"))

# ============================================================================
# Phase 1: Staged (pending invitation) index state
# ============================================================================

## Create invitation via staged relationship
@invitee_email = generate_unique_test_email("idx_lifecycle_invitee")
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee_email,
  role: 'member',
  inviter: @owner
)
@invitation.pending?
#=> true

## Staged: token_lookup is populated (find_by_token works)
@staged_token = @invitation.token
Onetime::OrganizationMembership.find_by_token(@staged_token).nil?
#=> false

## Staged: find_by_token returns the correct invitation
Onetime::OrganizationMembership.find_by_token(@staged_token).objid == @invitation.objid
#=> true

## Staged: find_pending_by_email discovers the invitation
Onetime::OrganizationMembership.find_pending_by_email(@org, @invitee_email).nil?
#=> false

# ============================================================================
# Phase 2: Active (accepted invitation) index state
# ============================================================================

## Create invitee customer and accept the invitation
@invitee = Onetime::Customer.create!(email: @invitee_email)
@invitation.accept!(@invitee)
@invitation.active?
#=> true

## Active: token_lookup is removed (token cleared for security)
Onetime::OrganizationMembership.find_by_token(@staged_token)
#=> nil

## Active: find_pending_by_email no longer discovers the membership (not pending)
Onetime::OrganizationMembership.find_pending_by_email(@org, @invitee_email)
#=> nil

## Active: find_by_org_customer works (direct composite key load)
@active_via_customer = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invitee.objid)
@active_via_customer.nil?
#=> false

## Active: find_by_org_customer returns an active membership
@active_via_customer.active?
#=> true

## Active: the in-memory invitation objid was updated to the composite key
@invitation.objid == @active_via_customer.objid
#=> true

# ============================================================================
# Phase 3: Revoked invitation index state
# ============================================================================

## Create a second invitation to test revoke index cleanup
@revoke_email = generate_unique_test_email("idx_lifecycle_revoke")
@revoke_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @revoke_email,
  role: 'member',
  inviter: @owner
)
@revoke_token = @revoke_invitation.token
@revoke_invitation.pending?
#=> true

## Pre-revoke: token_lookup is populated
Onetime::OrganizationMembership.find_by_token(@revoke_token).nil?
#=> false

## Pre-revoke: find_pending_by_email discovers the invitation
Onetime::OrganizationMembership.find_pending_by_email(@org, @revoke_email).nil?
#=> false

## Revoke the invitation (unstage)
@revoke_invitation.revoke!
#=> true

## Post-revoke: token_lookup is removed
Onetime::OrganizationMembership.find_by_token(@revoke_token)
#=> nil

## Post-revoke: find_pending_by_email no longer discovers the invitation
Onetime::OrganizationMembership.find_pending_by_email(@org, @revoke_email)
#=> nil

## Post-revoke: model is destroyed
Onetime::OrganizationMembership.load(@revoke_invitation.objid)
#=> nil

## Post-revoke: can re-invite the same email (staged set cleared)
@reinvite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @revoke_email,
  role: 'admin',
  inviter: @owner
)
@reinvite.pending?
#=> true
