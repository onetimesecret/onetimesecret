# try/integration/auth/signup_with_invite_try.rb
#
# frozen_string_literal: true

# Tests for AcceptInvitation operation during signup flow
#
# These tests verify that the AcceptInvitation operation:
# - Accepts valid pending invitations during account creation
# - Returns structured results for invalid/expired/mismatched tokens
# - Never raises exceptions that would block account creation
# - Properly links customer to organization with correct role
#
# Run: bundle exec try try/integration/auth/signup_with_invite_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

# Auth::Logging is required by accept_invitation but not auto-loaded
require 'web/auth/lib/logging'
require 'apps/web/auth/operations'

# Setup test data with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create an organization owner for sending invites
@owner_email = "invite_owner_#{@test_suffix}@onetimesecret.com"
@owner = Onetime::Customer.create!(email: @owner_email, role: 'customer')
@org = Onetime::Organization.create!(
  "Test Org #{@test_suffix}",
  @owner,
  @owner_email,
  is_default: true
)

# Create pending invitation for a new user
@invited_email = "invite_recipient_#{@test_suffix}@onetimesecret.com"
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invited_email,
  inviter: @owner,
  role: 'member'
)
@valid_token = @invitation.token

# Track created objects for teardown
@customers_to_cleanup = [@owner]
@invitations_to_cleanup = [@invitation]

## Test setup: Invitation is pending with valid token
[@invitation.pending?, @invitation.token.length > 20]
#=> [true, true]

## AcceptInvitation with valid token accepts the invitation
# Create a new customer matching the invited email
@new_customer = Onetime::Customer.create!(email: @invited_email, role: 'customer')
@customers_to_cleanup << @new_customer
result = Auth::Operations::AcceptInvitation.new(
  customer: @new_customer,
  token: @valid_token
).call
[result[:accepted], result[:organization_id] == @org.objid, result[:role]]
#=> [true, true, 'member']

## After acceptance, customer is verified (invite proves email ownership)
refreshed = Onetime::Customer.find_by_email(@invited_email)
[refreshed.verified?, refreshed.verified_by]
#=> [true, 'invite_token']

## After acceptance, invitation status is active
# After accept!, the UUID-keyed staged model is destroyed. Look up the activated
# composite-keyed membership via org+customer index instead of refresh! on the old key.
@activated = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @new_customer.objid)
@activated.active?
#=> true

## Customer is now a member of the organization
@org.member?(@new_customer)
#=> true

## AcceptInvitation with nil token returns no_token reason
result = Auth::Operations::AcceptInvitation.new(
  customer: @owner,
  token: nil
).call
[result[:accepted], result[:reason]]
#=> [false, 'no_token']

## AcceptInvitation with empty string token returns no_token reason
result = Auth::Operations::AcceptInvitation.new(
  customer: @owner,
  token: '  '
).call
[result[:accepted], result[:reason]]
#=> [false, 'no_token']

## AcceptInvitation with invalid token returns not_found reason
result = Auth::Operations::AcceptInvitation.new(
  customer: @owner,
  token: 'nonexistent_token_abc123'
).call
[result[:accepted], result[:reason]]
#=> [false, 'not_found']

## AcceptInvitation with already accepted invitation returns not_found (token cleared)
# The invitation from earlier test is now active, token was cleared on accept
@another_customer = Onetime::Customer.create!(
  email: "another_#{@test_suffix}@onetimesecret.com",
  role: 'customer'
)
@customers_to_cleanup << @another_customer
result = Auth::Operations::AcceptInvitation.new(
  customer: @another_customer,
  token: @valid_token
).call
# Token was cleared on accept, so this returns not_found
[result[:accepted], result[:reason]]
#=> [false, 'not_found']

## AcceptInvitation with email mismatch returns email_mismatch reason
# Create a fresh invitation
@mismatched_email = "mismatched_#{@test_suffix}@onetimesecret.com"
@mismatch_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @mismatched_email,
  inviter: @owner,
  role: 'admin'
)
@invitations_to_cleanup << @mismatch_invitation
# Try to accept with a customer that has a different email
@wrong_email_customer = Onetime::Customer.create!(
  email: "wrong_email_#{@test_suffix}@onetimesecret.com",
  role: 'customer'
)
@customers_to_cleanup << @wrong_email_customer
result = Auth::Operations::AcceptInvitation.new(
  customer: @wrong_email_customer,
  token: @mismatch_invitation.token
).call
[result[:accepted], result[:reason]]
#=> [false, 'email_mismatch']

## AcceptInvitation with expired invitation returns expired reason
# Create an invitation and manually backdate it
@expired_email = "expired_#{@test_suffix}@onetimesecret.com"
@expired_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @expired_invitation
# Backdate invited_at by 8 days (invitations expire after 7 days)
@expired_invitation.invited_at = Familia.now.to_f - (8 * 24 * 60 * 60)
@expired_invitation.save
@expired_customer = Onetime::Customer.create!(email: @expired_email, role: 'customer')
@customers_to_cleanup << @expired_customer
result = Auth::Operations::AcceptInvitation.new(
  customer: @expired_customer,
  token: @expired_invitation.token
).call
[result[:accepted], result[:reason]]
#=> [false, 'expired']

## AcceptInvitation normalizes email case for matching
# Create invitation with uppercase email
@case_email = "CaseTest_#{@test_suffix}@OneTimeSecret.COM"
@case_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @case_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @case_invitation
# Customer signs up with lowercase version
@case_customer = Onetime::Customer.create!(
  email: @case_email.downcase,
  role: 'customer'
)
@customers_to_cleanup << @case_customer
result = Auth::Operations::AcceptInvitation.new(
  customer: @case_customer,
  token: @case_invitation.token
).call
result[:accepted]
#=> true

## AcceptInvitation never raises, even with unexpected errors
# Simulate an error by passing a customer that causes issues in accept!
# The operation catches StandardError and returns a structured result
class BrokenCustomer
  attr_reader :email, :custid
  def initialize(email)
    @email = email
    @custid = 'broken-customer-id'
  end
  def objid
    raise StandardError, 'Simulated internal error'
  end
end
# Create a valid pending invitation for this test
@error_email = "error_test_#{@test_suffix}@onetimesecret.com"
@error_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @error_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @error_invitation
# BrokenCustomer has matching email so it passes validation, then fails in accept!
broken = BrokenCustomer.new(@error_email)
result = Auth::Operations::AcceptInvitation.new(
  customer: broken,
  token: @error_invitation.token
).call
# The error path changed after staged relationships migration: Familia's
# serialize_value now fails on the non-Familia BrokenCustomer object before
# objid is called. The key assertion is that the operation returns a safe
# error result without raising.
[result[:accepted], result[:reason], !result[:error].nil?]
#=> [false, 'error', true]

# Teardown - clean up test data
@customers_to_cleanup.each { |c| c&.destroy! rescue nil }
@invitations_to_cleanup.each { |inv| inv&.destroy_with_index_cleanup! rescue nil }
@org&.destroy! rescue nil
