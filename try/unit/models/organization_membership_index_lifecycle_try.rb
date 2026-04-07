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
#     - org_email_lookup: populated (prevents duplicate invitations)
#     - org_customer_lookup: NOT populated (customer_objid is nil)
#
#   ACTIVE (accepted invitation):
#     - token_lookup: removed (token cleared for security)
#     - org_email_lookup: repopulated with new composite-keyed objid
#     - org_customer_lookup: populated (enables find_by_org_customer)
#
#   REVOKED (via unstage):
#     - token_lookup: removed
#     - org_email_lookup: removed (allows re-invitation)
#     - org_customer_lookup: removed
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

## Staged: org_email_lookup is populated (find_by_org_email works)
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @invitee_email).nil?
#=> false

## Staged: org_customer_lookup is NOT populated (customer_objid is nil)
@invitation.org_customer_key
#=> nil

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

## Active: org_email_lookup still works but resolves to composite-keyed model
@active_via_email = Onetime::OrganizationMembership.find_by_org_email(@org.objid, @invitee_email)
@active_via_email.nil?
#=> false

## Active: org_email_lookup resolves to an active membership
@active_via_email.active?
#=> true

## Active: org_customer_lookup is populated (find_by_org_customer works)
@active_via_customer = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invitee.objid)
@active_via_customer.nil?
#=> false

## Active: find_by_org_customer returns an active membership
@active_via_customer.active?
#=> true

## Active: both lookups resolve to the same composite-keyed model
@active_via_email.objid == @active_via_customer.objid
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

## Pre-revoke: org_email_lookup is populated
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @revoke_email).nil?
#=> false

## Revoke the invitation (unstage)
@revoke_invitation.revoke!
#=> true

## Post-revoke: token_lookup is removed
Onetime::OrganizationMembership.find_by_token(@revoke_token)
#=> nil

## Post-revoke: org_email_lookup is removed (allows re-invitation)
Onetime::OrganizationMembership.find_by_org_email(@org.objid, @revoke_email)
#=> nil

## Post-revoke: model is destroyed
Onetime::OrganizationMembership.load(@revoke_invitation.objid)
#=> nil

## Post-revoke: can re-invite the same email (org_email_lookup cleared)
@reinvite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @revoke_email,
  role: 'admin',
  inviter: @owner
)
@reinvite.pending?
#=> true

## Re-invitation has a different objid than the revoked one
@reinvite.objid != @revoke_invitation.objid
#=> true

# Cleanup
@reinvite.destroy_with_index_cleanup! if @reinvite&.exists?
[@org, @owner, @invitee].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
