# try/unit/models/organization_membership_ensure_try.rb
#
# frozen_string_literal: true

#
# Tests OrganizationMembership.ensure_membership -- the application-level
# convergence point for all "add a known customer to an org" paths.
#
# ensure_membership composes two Familia primitives (activate + add) with
# a domain-specific lookup (find_by_org_email). It handles three cases:
#   1. Customer already a member -> returns existing membership (idempotent)
#   2. Pending invitation exists -> activates it (staged -> active)
#   3. No prior state -> creates membership directly (add)
#
# This ensures SSO auto-join, CLI add-member, and join request approval
# all converge to the same outcome regardless of whether a pending
# invitation exists.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("ensure_owner"))
@org = Onetime::Organization.create!("Ensure Membership Test Org", @owner, generate_unique_test_email("ensure_contact"))

## Direct add: creates active membership when no prior state exists
@direct_customer = Onetime::Customer.create!(email: generate_unique_test_email("ensure_direct"))
@direct_result = Onetime::OrganizationMembership.ensure_membership(@org, @direct_customer)
@direct_result.class
#=> Onetime::OrganizationMembership

## Direct add: membership is active
@direct_result.active?
#=> true

## Direct add: default role is 'member'
@direct_result.role
#=> 'member'

## Direct add: customer is in org.members
@org.member?(@direct_customer)
#=> true

## Direct add: reverse index populated
@direct_customer.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Direct add with explicit role
@admin_customer = Onetime::Customer.create!(email: generate_unique_test_email("ensure_admin"))
@admin_result = Onetime::OrganizationMembership.ensure_membership(@org, @admin_customer, role: 'admin')
@admin_result.role
#=> 'admin'

## Idempotent: returns existing membership when already a member
@existing_count = @org.member_count
@idempotent_result = Onetime::OrganizationMembership.ensure_membership(@org, @direct_customer)
@idempotent_result.objid == @direct_result.objid
#=> true

## Idempotent: member count unchanged
@org.member_count == @existing_count
#=> true

## Activates pending invitation when one exists
@invited_customer = Onetime::Customer.create!(email: generate_unique_test_email("ensure_invited"))
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invited_customer.email,
  role: 'member',
  inviter: @owner
)
@invitation.pending?
#=> true

## Pending invitation count is 1 before ensure_membership
@org.pending_invitation_count
#=> 1

## Capture staged objid before activation
@staged_objid = @invitation.objid

## ensure_membership activates the pending invitation
@activated_result = Onetime::OrganizationMembership.ensure_membership(@org, @invited_customer)
@activated_result.active?
#=> true

## Activated membership is findable by org+customer
@activated_result.objid == Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invited_customer.objid)&.objid
#=> true

## UUID-keyed staged model is destroyed after activation
Onetime::OrganizationMembership.load(@staged_objid)
#=> nil

## Staging set cleaned up after activation
@org.pending_invitation_count
#=> 0

## Reverse index populated via activation path
@invited_customer.organization_instances.any? { |o| o.objid == @org.objid }
#=> true

## Invitation role takes precedence over ensure_membership role arg
@role_customer = Onetime::Customer.create!(email: generate_unique_test_email("ensure_role"))
@role_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @role_customer.email,
  role: 'admin',
  inviter: @owner
)
@role_result = Onetime::OrganizationMembership.ensure_membership(@org, @role_customer, role: 'member')
@role_result.role
#=> 'admin'

## Expired invitation falls through to direct add (not raise)
@expired_customer = Onetime::Customer.create!(email: generate_unique_test_email("ensure_expired"))
@expired_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_customer.email,
  role: 'admin',
  inviter: @owner
)
# Backdate invited_at to make it expired (> 7 days)
@expired_invitation.invited_at = (Time.now - (8 * 24 * 60 * 60)).to_f
@expired_invitation.save
@expired_invitation.expired?
#=> true

## ensure_membership creates direct membership for expired invitation
@expired_result = Onetime::OrganizationMembership.ensure_membership(@org, @expired_customer, role: 'member')
@expired_result.active?
#=> true

## Direct add uses the role: arg (not the expired invitation's role)
@expired_result.role
#=> 'member'

## Customer is in org.members despite expired invitation
@org.member?(@expired_customer)
#=> true

## Declined invitation is no longer pending after decline!
@declined_customer = Onetime::Customer.create!(email: generate_unique_test_email("ensure_declined"))
@declined_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @declined_customer.email,
  role: 'admin',
  inviter: @owner
)
@declined_invitation.decline!
@declined_invitation.pending?
#=> false

## ensure_membership creates direct membership for declined invitation
@declined_result = Onetime::OrganizationMembership.ensure_membership(@org, @declined_customer, role: 'member')
@declined_result.active?
#=> true

# Cleanup
[@org, @owner, @direct_customer, @admin_customer, @invited_customer, @role_customer, @expired_customer, @declined_customer].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
