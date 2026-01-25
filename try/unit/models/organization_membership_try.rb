# try/unit/models/organization_membership_try.rb
#
# frozen_string_literal: true

#
# Unit tests for OrganizationMembership model
#
# Tests key functionality:
# - Role hierarchy: owner? includes owner, admin? includes owner+admin, member? includes all
# - membership_key generation (deterministic key format)
# - active_for_org returns only active memberships
# - Status checks (active?, pending?, expired?)
# - Invitation lifecycle (create, accept, decline, revoke)
#

require_relative '../../support/test_helpers'

OT.boot! :test

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: generate_unique_test_email("membership_owner"))
@admin = Onetime::Customer.create!(email: generate_unique_test_email("membership_admin"))
@member = Onetime::Customer.create!(email: generate_unique_test_email("membership_member"))
@org = Onetime::Organization.create!("Membership Test Org", @owner, generate_unique_test_email("membership_contact"))


# =============================================================================
# Role Hierarchy Tests
# =============================================================================

## Owner role: owner? returns true
@owner_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @owner.objid)
@owner_membership.owner?
#=> true

## Owner role: admin? returns true (owner includes admin)
@owner_membership.admin?
#=> true

## Owner role: member? returns true (owner includes member)
@owner_membership.member?
#=> true

## Admin role setup - create admin membership
@admin_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @admin.email,
  role: 'admin',
  inviter: @owner
)
@admin_invite.accept!(@admin)
@admin_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @admin.objid)
@admin_membership.role
#=> 'admin'

## Admin role: owner? returns false
@admin_membership.owner?
#=> false

## Admin role: admin? returns true
@admin_membership.admin?
#=> true

## Admin role: member? returns true (admin includes member)
@admin_membership.member?
#=> true

## Member role setup - create member membership
@member_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @member.email,
  role: 'member',
  inviter: @owner
)
@member_invite.accept!(@member)
@member_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @member.objid)
@member_membership.role
#=> 'member'

## Member role: owner? returns false
@member_membership.owner?
#=> false

## Member role: admin? returns false
@member_membership.admin?
#=> false

## Member role: member? returns true
@member_membership.member?
#=> true


# =============================================================================
# Status Check Tests
# =============================================================================

## Active membership: active? returns true
@owner_membership.active?
#=> true

## Active membership: pending? returns false
@owner_membership.pending?
#=> false

## Pending invitation: pending? returns true
@pending_email = generate_unique_test_email("pending_invitee")
@pending_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @pending_email,
  role: 'member',
  inviter: @owner
)
@pending_invite.pending?
#=> true

## Pending invitation: active? returns false
@pending_invite.active?
#=> false

## Pending invitation: expired? returns false (just created)
@pending_invite.expired?
#=> false


# =============================================================================
# active_for_org Tests
# =============================================================================

## active_for_org returns only active memberships
@active_memberships = Onetime::OrganizationMembership.active_for_org(@org)
@active_memberships.size
#=> 3

## active_for_org does not include pending invitations
@active_memberships.none?(&:pending?)
#=> true

## active_for_org includes owner
@active_memberships.any? { |m| m.customer_objid == @owner.objid }
#=> true

## active_for_org includes admin
@active_memberships.any? { |m| m.customer_objid == @admin.objid }
#=> true

## active_for_org includes member
@active_memberships.any? { |m| m.customer_objid == @member.objid }
#=> true


# =============================================================================
# Composite Index Key Tests
# =============================================================================

## org_customer_key format is correct for active membership
@owner_membership.org_customer_key
#=> "#{@org.objid}:#{@owner.objid}"

## org_email_key returns nil if invited_email is empty (active membership)
# Note: invited_email may still be set from invitation, but org_email_key checks both fields
@admin_membership.invited_email.nil? || @admin_membership.org_email_key.nil? || @admin_membership.org_email_key.include?(@admin.email.downcase)
#=> true

## org_email_key format is correct for pending invitation
@pending_invite.org_email_key
#=> "#{@org.objid}:#{@pending_email.downcase}"


# =============================================================================
# Lookup Method Tests
# =============================================================================

## find_by_org_customer returns correct membership
@found = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @owner.objid)
@found.objid == @owner_membership.objid
#=> true

## find_by_org_customer returns nil for non-member
@outsider = Onetime::Customer.create!(email: generate_unique_test_email("outsider"))
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @outsider.objid).nil?
#=> true

## find_by_token returns pending invitation
@found_by_token = Onetime::OrganizationMembership.find_by_token(@pending_invite.token)
@found_by_token.objid == @pending_invite.objid
#=> true

## find_by_token returns nil for invalid token
Onetime::OrganizationMembership.find_by_token("nonexistent_token").nil?
#=> true

## find_by_org_email returns pending invitation
@found_by_email = Onetime::OrganizationMembership.find_by_org_email(@org.objid, @pending_email)
@found_by_email.objid == @pending_invite.objid
#=> true


# =============================================================================
# Invitation Lifecycle Tests
# =============================================================================

## Accept invitation changes status to active
@accept_email = generate_unique_test_email("accept_invitee")
@accept_customer = Onetime::Customer.create!(email: @accept_email)
@accept_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @accept_email,
  role: 'member',
  inviter: @owner
)
@accept_invite.accept!(@accept_customer)
@accept_invite.active?
#=> true

## Accept invitation clears token
@accept_invite.token.nil?
#=> true

## Accept invitation sets joined_at
@accept_invite.joined_at.is_a?(Float)
#=> true

## Accept invitation adds customer to org members
@org.member?(@accept_customer)
#=> true

## Decline invitation changes status
@decline_email = generate_unique_test_email("decline_invitee")
@decline_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @decline_email,
  role: 'member',
  inviter: @owner
)
@decline_invite.decline!
@decline_invite.status
#=> 'declined'

## Decline invitation clears token
@decline_invite.token.nil?
#=> true

## Revoke invitation destroys the record
@revoke_email = generate_unique_test_email("revoke_invitee")
@revoke_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @revoke_email,
  role: 'member',
  inviter: @owner
)
@revoke_objid = @revoke_invite.objid
@revoke_invite.revoke!
@revoked_check = Onetime::OrganizationMembership.load(@revoke_objid)
@revoked_check.nil? || !@revoked_check.exists?
#=> true


# =============================================================================
# Error Handling Tests
# =============================================================================

## Cannot create duplicate pending invitation
@dup_error = begin
  Onetime::OrganizationMembership.create_invitation!(
    organization: @org,
    email: @pending_email,
    role: 'member',
    inviter: @owner
  )
  nil
rescue Onetime::Problem => e
  e.message
end
@dup_error.include?('already pending')
#=> true

## Cannot accept already active invitation
@accept_error = begin
  @accept_invite.accept!(@accept_customer)
  nil
rescue Onetime::Problem => e
  e.message
end
@accept_error.include?('already accepted')
#=> true

## Cannot decline active membership
@decline_error = begin
  @accept_invite.decline!
  nil
rescue Onetime::Problem => e
  e.message
end
@decline_error.include?('Cannot decline active')
#=> true

## Cannot revoke active membership (only pending)
@revoke_error = begin
  @accept_invite.revoke!
  nil
rescue Onetime::Problem => e
  e.message
end
@revoke_error.include?('pending')
#=> true


# Cleanup
[@org, @owner, @admin, @member, @outsider, @accept_customer].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
