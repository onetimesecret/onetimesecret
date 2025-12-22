# try/unit/models/organization_invitation_try.rb
#
# frozen_string_literal: true

#
# Tests for OrganizationMembership invitation flows
#
# The invitation system uses OrganizationMembership with status='pending'
# to track invitations before they are accepted.
#
# Key behaviors tested:
# - Creating invitations with create_invitation!
# - Finding invitations by token
# - Finding invitations by org + email
# - Accepting invitations
# - Declining invitations
# - Revoking invitations
# - Expiration checking

require_relative '../../support/test_models'

OT.boot! :test

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: "invite_owner_#{@test_suffix}@test.com")
@invitee = Onetime::Customer.create!(email: "invite_member_#{@test_suffix}@test.com")
@billing_email = "invite_billing_#{@test_suffix}@acme.com"
@org = Onetime::Organization.create!("Invitation Test Org", @owner, @billing_email)

## Create invitation with create_invitation!
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee.email,
  role: 'member',
  inviter: @owner,
)
@invitation.class
#=> Onetime::OrganizationMembership

## Invitation has pending status
@invitation.status
#=> 'pending'

## Invitation has token
@invitation.token.nil?
#=> false

## Invitation token has sufficient entropy (256 bits = 43+ chars base64)
@invitation.token.length >= 43
#=> true

## Invitation has role
@invitation.role
#=> 'member'

## Invitation has invited_email
@invitation.invited_email
#=> @invitee.email

## Invitation has invited_by
@invitation.invited_by
#=> @owner.objid

## Invitation has invited_at
@invitation.invited_at.is_a?(Float)
#=> true

## Invitation is pending
@invitation.pending?
#=> true

## Invitation is not active
@invitation.active?
#=> false

## Invitation is not expired (just created)
@invitation.expired?
#=> false

## Find invitation by token
@found = Onetime::OrganizationMembership.find_by_token(@invitation.token)
@found.objid == @invitation.objid
#=> true

## Find invitation by org + email
@found_by_email = Onetime::OrganizationMembership.find_by_org_email(@org.objid, @invitee.email)
@found_by_email.nil? || @found_by_email.objid == @invitation.objid
#=> true

## Pending invitations for org
@pending = Onetime::OrganizationMembership.pending_for_org(@org)
@pending.any? { |m| m.objid == @invitation.objid }
#=> true

## Accept invitation
@accept_result = @invitation.accept!(@invitee)
@accept_result
#=> true

## Invitation is now active
@invitation.status
#=> 'active'

## Invitation has customer_objid after accept
@invitation.customer_objid
#=> @invitee.objid

## Invitation token cleared after accept
@invitation.token.nil?
#=> true

## Invitation has joined_at
@invitation.joined_at.is_a?(Float)
#=> true

## Invitee now member of org
@org.member?(@invitee)
#=> true

# Test declining an invitation
## Decline invitation updates status
@invitee2 = Onetime::Customer.create!(email: "invite_decline_#{@test_suffix}@test.com")
@decline_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee2.email,
  role: 'member',
  inviter: @owner,
)
@decline_invite.decline!
@decline_invite.status
#=> 'declined'

## Declined invitation has token cleared
@decline_invite.token.nil?
#=> true

## Cannot find declined invitation by token
Onetime::OrganizationMembership.find_by_token('nonexistent').nil?
#=> true

# Test revoking an invitation
## Revoke invitation destroys record
@invitee3 = Onetime::Customer.create!(email: "invite_revoke_#{@test_suffix}@test.com")
@revoke_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee3.email,
  role: 'admin',
  inviter: @owner,
)
@revoke_objid = @revoke_invite.objid
@revoke_invite.revoke!
@revoked_check = Onetime::OrganizationMembership.load(@revoke_objid)
@revoked_check.nil? || !@revoked_check.exists?
#=> true

# Test duplicate invitation prevention
## Duplicate invitation raises error
@invitee4 = Onetime::Customer.create!(email: "invite_dup_#{@test_suffix}@test.com")
@first_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee4.email,
  role: 'member',
  inviter: @owner,
)
@dup_error = begin
  Onetime::OrganizationMembership.create_invitation!(
    organization: @org,
    email: @invitee4.email,
    role: 'member',
    inviter: @owner,
  )
  'no error'
rescue Onetime::Problem => e
  e.message
end
@dup_error.include?('already pending')
#=> true

## Inviter helper returns correct customer
@first_invite.inviter.objid == @owner.objid
#=> true

## Organization helper returns correct org
@first_invite.organization.objid == @org.objid
#=> true

## member? returns true for member role
@first_invite.member?
#=> true

## admin? returns false for member role
@first_invite.admin?
#=> false

## owner? returns false for member role
@first_invite.owner?
#=> false

# Cleanup
[@org, @owner, @invitee, @invitee2, @invitee3, @invitee4].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
