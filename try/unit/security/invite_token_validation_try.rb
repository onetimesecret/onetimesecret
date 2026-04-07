# try/unit/security/invite_token_validation_try.rb
#
# frozen_string_literal: true

# Security tests for invite token validation logic used in send_verify_account_email.
#
# After Fix 1, the send_verify_account_email hook validates invite_token by:
#   1. Looking up via OrganizationMembership.find_by_token(token)
#   2. Checking invitation.pending?
#   3. Checking !invitation.expired?
#   4. Checking normalized email match between invitation and signup
#
# If ANY check fails, the verification email is sent normally (super()).
# This prevents email squatting via garbage invite_token params.
#
# These tests exercise the same validation predicates the hook uses,
# ensuring each gate correctly allows/blocks email suppression.
#
# Run: bundle exec try try/unit/security/invite_token_validation_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'web/auth/lib/logging'
require 'apps/web/auth/operations'

@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create organization owner
@owner_email = generate_unique_test_email('tokval_owner')
@owner = Onetime::Customer.create!(email: @owner_email, role: 'customer')
@org = Onetime::Organization.create!(
  "Token Validation Org #{@test_suffix}",
  @owner,
  @owner_email,
  is_default: true
)

# Create a valid pending invitation
@invited_email = generate_unique_test_email('tokval_invited')
@invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invited_email,
  inviter: @owner,
  role: 'member'
)
@valid_token = @invitation.token

# Track objects for teardown
@customers_to_cleanup = [@owner]
@invitations_to_cleanup = [@invitation]

## find_by_token returns nil for a garbage token string
# This is the core of Fix 1: garbage tokens must not suppress the verification email.
# Before the fix, raw param presence was enough to skip the email.
Onetime::OrganizationMembership.find_by_token('garbage_token_abc123')
#=> nil

## find_by_token returns nil for an empty string
Onetime::OrganizationMembership.find_by_token('')
#=> nil

## find_by_token returns nil for nil
Onetime::OrganizationMembership.find_by_token(nil)
#=> nil

## find_by_token returns nil for a UUID-shaped but nonexistent token
Onetime::OrganizationMembership.find_by_token('550e8400-e29b-41d4-a716-446655440000')
#=> nil

## find_by_token returns the invitation for a valid token
found = Onetime::OrganizationMembership.find_by_token(@valid_token)
found.nil? == false
#=> true

## Valid invitation is pending
@invitation.pending?
#=> true

## Valid invitation is not expired
@invitation.expired?
#=> false

## Simulating the send_verify_account_email gate: valid token, pending, not expired, email match
# This mirrors the exact conditional in account_management.rb lines 33-38.
# When all conditions pass, email should be suppressed (should_suppress = true).
invitation = Onetime::OrganizationMembership.find_by_token(@valid_token)
should_suppress = invitation &&
                  invitation.pending? &&
                  !invitation.expired? &&
                  OT::Utils.normalize_email(invitation.invited_email) ==
                    OT::Utils.normalize_email(@invited_email)
should_suppress
#=> true

## Gate with garbage token: email must NOT be suppressed
invitation = Onetime::OrganizationMembership.find_by_token('garbage_token_abc123')
should_suppress = invitation &&
                  invitation.pending? &&
                  !invitation.expired?
should_suppress
#=> nil

## Gate with expired invitation: email must NOT be suppressed
@expired_email = generate_unique_test_email('tokval_expired')
@expired_invitation = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @expired_email,
  inviter: @owner,
  role: 'member'
)
@invitations_to_cleanup << @expired_invitation
# Backdate by 8 days (invitations expire after 7 days)
@expired_invitation.invited_at = Familia.now.to_f - (8 * 24 * 60 * 60)
@expired_invitation.save
expired_inv = Onetime::OrganizationMembership.find_by_token(@expired_invitation.token)
should_suppress = expired_inv &&
                  expired_inv.pending? &&
                  !expired_inv.expired? &&
                  OT::Utils.normalize_email(expired_inv.invited_email) ==
                    OT::Utils.normalize_email(@expired_email)
should_suppress
#=> false

## Gate with email mismatch: email must NOT be suppressed
# Invitation is for @invited_email, but signup email is different
invitation = Onetime::OrganizationMembership.find_by_token(@valid_token)
wrong_signup_email = "attacker_#{@test_suffix}@evil.com"
should_suppress = invitation &&
                  invitation.pending? &&
                  !invitation.expired? &&
                  OT::Utils.normalize_email(invitation.invited_email) ==
                    OT::Utils.normalize_email(wrong_signup_email)
should_suppress
#=> false

## Gate with non-pending (already accepted) invitation: email must NOT be suppressed
# Accept the invitation first to change its status
@new_customer = Onetime::Customer.create!(email: @invited_email, role: 'customer')
@customers_to_cleanup << @new_customer
Auth::Operations::AcceptInvitation.new(
  customer: @new_customer,
  token: @valid_token
).call
# Token is cleared on accept, so find_by_token returns nil
post_accept = Onetime::OrganizationMembership.find_by_token(@valid_token)
should_suppress = post_accept &&
                  post_accept.pending? &&
                  !post_accept.expired?
# nil is falsy, so email will not be suppressed
post_accept.nil?
#=> true

## Expired invitation: expired? returns true
@expired_invitation.expired?
#=> true

## Expired invitation: pending? still returns true (status unchanged)
# expired? is a time check, not a status change. The invitation is still
# in pending status but has exceeded its TTL.
@expired_invitation.pending?
#=> true

## normalize_email is case-insensitive for the email gate
# Ensures the email comparison in the hook uses case-folding
upper = OT::Utils.normalize_email('USER@EXAMPLE.COM')
lower = OT::Utils.normalize_email('user@example.com')
upper == lower
#=> true

## normalize_email strips whitespace
OT::Utils.normalize_email('  user@example.com  ') == OT::Utils.normalize_email('user@example.com')
#=> true

# Teardown
@customers_to_cleanup.each { |c| c&.destroy! rescue nil }
@invitations_to_cleanup.each { |inv| inv&.destroy_with_index_cleanup! rescue nil }
@org&.destroy! rescue nil
