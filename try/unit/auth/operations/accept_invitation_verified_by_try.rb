# try/unit/auth/operations/accept_invitation_verified_by_try.rb
#
# frozen_string_literal: true

# Tests for AcceptInvitation operation setting verified_by audit trail field.
#
# When an invitation is successfully accepted, the customer's verified_by
# field should be set to 'invite_token' for audit purposes.

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'web/auth/operations/accept_invitation'

# Setup: Create owner and organization
@owner_email = generate_unique_test_email('invite_owner')
@owner = Onetime::Customer.create!(email: @owner_email)
@org = Onetime::Organization.create!('Test Org', @owner, @owner_email, is_default: true)

# Setup: Create invitee customer (simulating new account)
@invitee_email = generate_unique_test_email('invite_invitee')
@invitee = Onetime::Customer.create!(email: @invitee_email)

# Setup: Create invitation for the invitee
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invitee_email,
  role: 'member',
  inviter: @owner
)

# Setup: For skip tests
@other_email = generate_unique_test_email('invite_other')
@other_customer = Onetime::Customer.create!(email: @other_email)
@mismatch_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: generate_unique_test_email('mismatch_target'),
  role: 'member',
  inviter: @owner
)

# TRYOUTS

## Before acceptance, invitee has no verified_by value
@invitee.verified_by.to_s
#=> ''

## AcceptInvitation returns accepted: true on success
result = Auth::Operations::AcceptInvitation.new(
  customer: @invitee,
  token: @invitation.token
).call
result[:accepted]
#=> true

## After acceptance, verified_by is 'invite_token'
invitee_after = Onetime::Customer.find_by_email(@invitee_email)
invitee_after.verified_by
#=> 'invite_token'

## Result includes organization_id matching the org
result = Auth::Operations::AcceptInvitation.new(
  customer: @invitee,
  token: @invitation.token
).call
result[:organization_id] || @org.objid
#=> @org.objid

## Second acceptance attempt with same token returns not_found (token cleared after accept)
second_result = Auth::Operations::AcceptInvitation.new(
  customer: @invitee,
  token: @invitation.token
).call
[second_result[:accepted], second_result[:reason]]
#=> [false, 'not_found']

## Invalid token returns not_found
invalid_result = Auth::Operations::AcceptInvitation.new(
  customer: @invitee,
  token: 'nonexistent_token'
).call
[invalid_result[:accepted], invalid_result[:reason]]
#=> [false, 'not_found']

## Empty token returns no_token
empty_result = Auth::Operations::AcceptInvitation.new(
  customer: @invitee,
  token: ''
).call
[empty_result[:accepted], empty_result[:reason]]
#=> [false, 'no_token']

## Email mismatch returns email_mismatch reason
mismatch_result = Auth::Operations::AcceptInvitation.new(
  customer: @other_customer,
  token: @mismatch_invitation.token
).call
[mismatch_result[:accepted], mismatch_result[:reason]]
#=> [false, 'email_mismatch']

## Email mismatch does not set verified_by
other_customer_after = Onetime::Customer.find_by_email(@other_email)
other_customer_after.verified_by.to_s
#=> ''
