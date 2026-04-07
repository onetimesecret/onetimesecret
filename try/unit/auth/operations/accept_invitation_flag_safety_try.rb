# try/unit/auth/operations/accept_invitation_flag_safety_try.rb
#
# frozen_string_literal: true

# Tests for the safety properties that Fix 3 depends on.
#
# Fix 3 moved @invite_accepted = true to AFTER the DB operations
# (update_account, remove_verify_account_key) in the after_create_account hook.
# If those operations raise, the flag stays falsy and autologin won't fire.
#
# The hook uses safe_execute which catches StandardError and returns nil on failure.
# AcceptInvitation itself catches StandardError and returns { accepted: false }.
#
# These tests verify:
# - AcceptInvitation returns accepted: false on internal errors
# - AcceptInvitation returns accepted: false for every invalid-token scenario
# - A caller checking result[:accepted] before setting a flag will correctly
#   skip flag-setting when the operation fails
#
# Run: bundle exec try try/unit/auth/operations/accept_invitation_flag_safety_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'web/auth/lib/logging'
require 'apps/web/auth/operations'

@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create organization owner
@owner_email = generate_unique_test_email('flag_owner')
@owner = Onetime::Customer.create!(email: @owner_email, role: 'customer')
@org = Onetime::Organization.create!(
  "Flag Safety Org #{@test_suffix}",
  @owner,
  @owner_email,
  is_default: true
)

# Track objects for teardown
@customers_to_cleanup = [@owner]
@invitations_to_cleanup = []

## Simulating the hook pattern: flag stays falsy when AcceptInvitation returns not accepted
# This mirrors the after_create_account hook logic:
#   result = AcceptInvitation.new(...).call
#   if result[:accepted]
#     update_account(...)
#     remove_verify_account_key(...)
#     @invite_accepted = true   # <-- only reached if above succeeds
#   end
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: @owner,
  token: 'garbage_token'
).call
if result[:accepted]
  invite_accepted = true
end
invite_accepted.nil?
#=> true

## Flag stays falsy for nil token
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: @owner,
  token: nil
).call
invite_accepted = true if result[:accepted]
invite_accepted.nil?
#=> true

## Flag stays falsy for empty token
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: @owner,
  token: ''
).call
invite_accepted = true if result[:accepted]
invite_accepted.nil?
#=> true

## Flag stays falsy for expired invitation
@expired_email = generate_unique_test_email('flag_expired')
@expired_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @expired_invitation
@expired_invitation.invited_at = Familia.now.to_f - (8 * 24 * 60 * 60)
@expired_invitation.save
@expired_customer = Onetime::Customer.create!(email: @expired_email, role: 'customer')
@customers_to_cleanup << @expired_customer
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: @expired_customer,
  token: @expired_invitation.token
).call
invite_accepted = true if result[:accepted]
[invite_accepted.nil?, result[:reason]]
#=> [true, 'expired']

## Flag stays falsy for email mismatch
@mismatch_email = generate_unique_test_email('flag_mismatch')
@mismatch_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @mismatch_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @mismatch_invitation
@wrong_customer = Onetime::Customer.create!(
  email: generate_unique_test_email('flag_wrong'),
  role: 'customer'
)
@customers_to_cleanup << @wrong_customer
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: @wrong_customer,
  token: @mismatch_invitation.token
).call
invite_accepted = true if result[:accepted]
[invite_accepted.nil?, result[:reason]]
#=> [true, 'email_mismatch']

## Flag stays falsy when AcceptInvitation catches an internal error
class FaultyCustomer
  attr_reader :email, :custid
  def initialize(email)
    @email = email
    @custid = 'faulty-id'
  end
  def objid
    raise StandardError, 'Simulated DB failure'
  end
end
@error_email = generate_unique_test_email('flag_error')
@error_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @error_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @error_invitation
faulty = FaultyCustomer.new(@error_email)
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: faulty,
  token: @error_invitation.token
).call
invite_accepted = true if result[:accepted]
[invite_accepted.nil?, result[:reason]]
#=> [true, 'error']

## Flag becomes true only on successful acceptance
@valid_email = generate_unique_test_email('flag_valid')
@valid_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @valid_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @valid_invitation
@valid_customer = Onetime::Customer.create!(email: @valid_email, role: 'customer')
@customers_to_cleanup << @valid_customer
invite_accepted = nil
result = Auth::Operations::AcceptInvitation.new(
  customer: @valid_customer,
  token: @valid_invitation.token
).call
invite_accepted = true if result[:accepted]
[invite_accepted, result[:accepted]]
#=> [true, true]

## create_account_autologin? pattern: @invite_accepted == true is false when nil
# The hook uses `@invite_accepted == true` (not just truthy check).
# This tests that nil == true is false.
invite_accepted = nil
invite_accepted == true
#=> false

## create_account_autologin? pattern: false == true is false
invite_accepted = false
invite_accepted == true
#=> false

## create_account_autologin? pattern: only true == true is true
invite_accepted = true
invite_accepted == true
#=> true

# Teardown
@customers_to_cleanup.each { |c| c&.destroy! rescue nil }
@invitations_to_cleanup.each { |inv| inv&.destroy_with_index_cleanup! rescue nil }
@org&.destroy! rescue nil
