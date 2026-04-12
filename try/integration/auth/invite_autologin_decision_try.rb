# try/integration/auth/invite_autologin_decision_try.rb
#
# frozen_string_literal: true

# Tests for the autologin decision logic during invite signup.
#
# After the invite acceptance fix, the after_create_account hook sets
# @invite_accepted = true ONLY after:
#   1. AcceptInvitation succeeds (result[:accepted] == true)
#   2. Account is auto-verified at SQL level
#   3. Verify key is removed
#
# The create_account_autologin? block then checks @invite_accepted to
# decide whether to auto-login the new user.
#
# These tests verify the AcceptInvitation result structure that drives
# the autologin decision, and the verification side-effects that must
# succeed before autologin fires.
#
# Run: bundle exec try try/integration/auth/invite_autologin_decision_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'web/auth/lib/logging'
require 'apps/web/auth/operations'

@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create organization owner
@owner_email = generate_unique_test_email('autologin_owner')
@owner = Onetime::Customer.create!(email: @owner_email, role: 'customer')
@org = Onetime::Organization.create!(
  "Autologin Test Org #{@test_suffix}",
  @owner,
  @owner_email,
  is_default: true
)

# Track objects for teardown
@customers_to_cleanup = [@owner]
@invitations_to_cleanup = []

## AcceptInvitation result includes :accepted key for autologin gate
@invited_email = generate_unique_test_email('autologin_invited')
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invited_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @invitation
@customer = Onetime::Customer.create!(email: @invited_email, role: 'customer')
@customers_to_cleanup << @customer
@accept_result = Auth::Operations::AcceptInvitation.new(
  customer: @customer,
  token: @invitation.token
).call
@accept_result.key?(:accepted)
#=> true

## Successful acceptance sets accepted to true (autologin should fire)
@accept_result[:accepted]
#=> true

## Successful acceptance includes organization_id for logging
@accept_result[:organization_id] == @org.objid
#=> true

## Successful acceptance includes role for logging
@accept_result[:role]
#=> 'member'

## Customer is auto-verified after acceptance (invite proves email ownership)
@refreshed = Onetime::Customer.find_by_email(@invited_email)
@refreshed.verified?
#=> true

## Customer verified_by is set to 'invite_token' (audit trail)
@refreshed = Onetime::Customer.find_by_email(@invited_email)
@refreshed.verified_by
#=> 'invite_token'

## Failed acceptance sets accepted to false (autologin must NOT fire)
@bad_customer = Onetime::Customer.create!(
  email: generate_unique_test_email('autologin_bad'),
  role: 'customer'
)
@customers_to_cleanup << @bad_customer
@bad_result = Auth::Operations::AcceptInvitation.new(
  customer: @bad_customer,
  token: 'invalid_token_xyz'
).call
@bad_result[:accepted]
#=> false

## Failed acceptance includes reason for logging
@bad_result[:reason]
#=> 'not_found'

## Nil token returns accepted: false (no autologin for normal signups)
@nil_result = Auth::Operations::AcceptInvitation.new(
  customer: @bad_customer,
  token: nil
).call
@nil_result[:accepted]
#=> false

## Nil token returns reason: no_token
@nil_result[:reason]
#=> 'no_token'

## Empty token returns accepted: false (no autologin for normal signups)
@empty_result = Auth::Operations::AcceptInvitation.new(
  customer: @bad_customer,
  token: '  '
).call
@empty_result[:accepted]
#=> false

## Email mismatch returns accepted: false (autologin must NOT fire)
@mismatch_email = generate_unique_test_email('autologin_mismatch')
@mismatch_inv = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @mismatch_email,
  inviter: @owner,
  role: 'admin'
)
@invitations_to_cleanup << @mismatch_inv
@mismatch_result = Auth::Operations::AcceptInvitation.new(
  customer: @bad_customer,
  token: @mismatch_inv.token
).call
[@mismatch_result[:accepted], @mismatch_result[:reason]]
#=> [false, 'email_mismatch']

## Expired invite returns accepted: false (autologin must NOT fire)
@expired_email = generate_unique_test_email('autologin_expired')
@expired_inv = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @expired_inv
@expired_inv.invited_at = Familia.now.to_f - (8 * 24 * 60 * 60)
@expired_inv.save
@expired_customer = Onetime::Customer.create!(email: @expired_email, role: 'customer')
@customers_to_cleanup << @expired_customer
@expired_result = Auth::Operations::AcceptInvitation.new(
  customer: @expired_customer,
  token: @expired_inv.token
).call
[@expired_result[:accepted], @expired_result[:reason]]
#=> [false, 'expired']

# Teardown
@customers_to_cleanup.each { |c| c&.destroy! rescue nil }
@invitations_to_cleanup.each { |inv| inv&.destroy_with_index_cleanup! rescue nil }
@org&.destroy! rescue nil
