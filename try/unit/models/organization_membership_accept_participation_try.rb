# try/unit/models/organization_membership_accept_participation_try.rb
#
# frozen_string_literal: true

#
# Tests the staged relationship lifecycle for organization invitations.
#
# Regression test for GitHub issue #2903:
#   "Invited members don't see organization in their org list after accepting."
#
# The original bug: accept! called org.members.add(customer, score) but did NOT
# call customer.track_participation_in(org.members.dbkey), so the customer's
# reverse index was never populated and organization_instances returned [].
#
# The fix: migrate invitation flow to Familia's staged relationships API which
# handles the three-structure invariant atomically:
#   1. Active set (org.members)
#   2. Reverse index (customer.organization_instances)
#   3. Staging set (org.pending_invitations)
#
# Key behaviors tested:
# - Staged model is UUID-keyed, not composite-keyed
# - Staging set tracks pending invitations correctly
# - After accept!, customer appears in org.members (forward index)
# - After accept!, org appears in customer.organization_instances (reverse index)
# - After accept!, UUID-keyed staged model is destroyed
# - After accept!, composite-keyed model is findable via find_by_org_customer
# - Unstage (revoke) clears the staging set and destroys the model
# - Multiple invitees each get their own reverse index entry

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("accept_part_owner"))
@invitee = Onetime::Customer.create!(email: generate_unique_test_email("accept_part_invitee"))
@org = Onetime::Organization.create!("Accept Participation Test Org", @owner, generate_unique_test_email("accept_part_contact"))

## Owner has org in organization_instances after create
@owner.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Invitee has no organizations before accepting invitation
@invitee.organization_instances.size
#=> 0

## No pending invitations initially (owner was added directly, not staged)
@org.pending_invitation_count
#=> 0

## Create pending invitation for invitee
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee.email,
  role: 'member',
  inviter: @owner
)
@invitation.pending?
#=> true

## Staged model has a UUID-based objid (not composite key format)
# Composite keys look like "organization:{org_objid}:customer:{cust_objid}:org_membership"
# UUID keys are shorter and don't contain the composite pattern
@invitation.objid.include?(':customer:') == false
#=> true

## Pending invitations count is 1 after staging
@org.pending_invitation_count
#=> 1

## Staged model is in the pending_invitations set
@org.pending_invitations.member?(@invitation.objid)
#=> true

## Invitee still has no organizations while invitation is pending
@invitee.organization_instances.size
#=> 0

## Capture the staged model's UUID objid before acceptance
@staged_objid = @invitation.objid

## Accept the invitation
@invitation.accept!(@invitee)
@invitation.active?
#=> true

## Forward index: invitee appears in org.members
@org.member?(@invitee)
#=> true

## Reverse index: org appears in invitee's organization_instances (regression #2903)
@invitee.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Reverse index: invitee has exactly one organization
@invitee.organization_instances.size
#=> 1

## UUID-keyed staged model is destroyed after acceptance
Onetime::OrganizationMembership.load(@staged_objid)
#=> nil

## Composite-keyed model is findable via find_by_org_customer after acceptance
@activated = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invitee.objid)
@activated.nil?
#=> false

## Activated model has active status
@activated.status
#=> 'active'

## Activated model has the correct role carried over from invitation
@activated.role
#=> 'member'

## Pending invitations count is 0 after acceptance (staging set cleaned up)
@org.pending_invitation_count
#=> 0

## Owner's reverse index is unchanged (still has exactly one org)
@owner.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Second invitee also gets reverse index populated after accept
@invitee2 = Onetime::Customer.create!(email: generate_unique_test_email("accept_part_invitee2"))
@invitation2 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee2.email,
  role: 'admin',
  inviter: @owner
)
@invitation2.accept!(@invitee2)
@invitee2.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Second invitee has exactly one organization
@invitee2.organization_instances.size
#=> 1

## Org now has three members (owner + two invitees)
Onetime::OrganizationMembership.active_for_org(@org).size
#=> 3

# --- Unstage (revoke) tests ---

## Create invitation to be revoked
@invitee3 = Onetime::Customer.create!(email: generate_unique_test_email("accept_part_revoke"))
@invitation3 = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee3.email,
  role: 'member',
  inviter: @owner
)
@revoke_objid = @invitation3.objid
@org.pending_invitation_count
#=> 1

## Revoke the invitation (unstage)
@invitation3.revoke!
@org.pending_invitation_count
#=> 0

## Revoked model is destroyed
Onetime::OrganizationMembership.load(@revoke_objid)
#=> nil

## Revoked invitee's org list is still empty
@invitee3.organization_instances.size
#=> 0

# Cleanup
[@org, @owner, @invitee, @invitee2, @invitee3].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
