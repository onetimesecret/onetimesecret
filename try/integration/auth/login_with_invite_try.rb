# try/integration/auth/login_with_invite_try.rb
#
# frozen_string_literal: true

# Integration tests for login with invite_token parameter.
#
# Tests that the after_login hook in login.rb accepts pending invitations
# when an invite_token is provided in the login request.
#
# NOTE: Full Rodauth login flow testing requires a complete auth stack setup.
# These tests verify the AcceptInvitation operation can be called in the
# context expected by the after_login hook.

require_relative '../../support/test_helpers'

OT.boot! :test

require 'web/auth/operations/accept_invitation'

# Setup: Create organization owner
@owner_email = generate_unique_test_email('login_owner')
@owner = Onetime::Customer.create!(email: @owner_email)
@org = Onetime::Organization.create!('Login Test Org', @owner, @owner_email, is_default: true)

# Setup: Existing user with pending invitation
@existing_email = generate_unique_test_email('login_existing')
@existing_user = Onetime::Customer.create!(email: @existing_email)
@existing_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @existing_email,
  role: 'member',
  inviter: @owner
)

# Setup: User with no invitation for skip tests
@no_invite_email = generate_unique_test_email('login_noinvite')
@no_invite_user = Onetime::Customer.create!(email: @no_invite_email)

# Setup: User and invitation for email mismatch scenario
@mismatch_email = generate_unique_test_email('login_mismatch')
@mismatch_user = Onetime::Customer.create!(email: @mismatch_email)
@mismatch_target_email = generate_unique_test_email('mismatch_target')
@mismatch_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @mismatch_target_email,
  role: 'admin',
  inviter: @owner
)

# TRYOUTS

## Invitation is pending before login
@existing_invitation.pending?
#=> true

## AcceptInvitation succeeds when called with correct customer and token
accept_result = Auth::Operations::AcceptInvitation.new(
  customer: @existing_user,
  token: @existing_invitation.token
).call
accept_result[:accepted]
#=> true

## Customer verified_by is set to invite_token after acceptance
existing_user_after = Onetime::Customer.find_by_email(@existing_email)
existing_user_after.verified_by
#=> 'invite_token'

## Customer is now a member of the organization
members = @org.members.to_a
member_objids = members.map { |m| m.is_a?(String) ? m : m.customer_objid }
member_objids.include?(@existing_user.objid)
#=> true

## AcceptInvitation with invalid token returns skip result
invalid_result = Auth::Operations::AcceptInvitation.new(
  customer: @no_invite_user,
  token: 'invalid_token_xyz'
).call
[invalid_result[:accepted], invalid_result[:reason]]
#=> [false, 'not_found']

## Customer verified_by remains unset for failed acceptance
no_invite_user_after = Onetime::Customer.find_by_email(@no_invite_email)
no_invite_user_after.verified_by.to_s
#=> ''

## AcceptInvitation with empty token returns skip result
empty_result = Auth::Operations::AcceptInvitation.new(
  customer: @no_invite_user,
  token: ''
).call
[empty_result[:accepted], empty_result[:reason]]
#=> [false, 'no_token']

## AcceptInvitation with nil token returns skip result
nil_result = Auth::Operations::AcceptInvitation.new(
  customer: @no_invite_user,
  token: nil
).call
[nil_result[:accepted], nil_result[:reason]]
#=> [false, 'no_token']

## AcceptInvitation with mismatched email returns email_mismatch
mismatch_result = Auth::Operations::AcceptInvitation.new(
  customer: @mismatch_user,
  token: @mismatch_invitation.token
).call
[mismatch_result[:accepted], mismatch_result[:reason]]
#=> [false, 'email_mismatch']

## Invitation remains pending after mismatch
@mismatch_invitation.pending?
#=> true
