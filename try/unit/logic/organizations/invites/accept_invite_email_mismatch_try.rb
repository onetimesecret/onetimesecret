# try/unit/logic/organizations/invites/accept_invite_email_mismatch_try.rb
#
# frozen_string_literal: true

#
# Tests for AcceptInvite strict email matching logic.
#
# Phase 4 Security Change: Email mismatch acknowledgment has been removed.
# Invitations are now strictly email-bound - no exceptions.
#
# Tests cover:
# 1. Exact email match - accepts
# 2. Case difference only - accepts (case-insensitive)
# 3. Different emails - always rejects (no acknowledgment bypass)
# 4. Plus-tag difference - rejects (treated as different email)

require_relative '../../../../support/test_models'
require 'securerandom'

# Load InviteAPI logic
app_root = File.join(ENV['ONETIME_HOME'], 'apps')
$LOAD_PATH.unshift(app_root) unless $LOAD_PATH.include?(app_root)

require 'api/invite/logic'

OT.boot! :test

# Clean up any existing test data
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create owner and organization
@owner = Onetime::Customer.create!(email: "accept_owner_#{@test_suffix}@test.com")
@billing_email = "accept_billing_#{@test_suffix}@acme.com"
@org = Onetime::Organization.create!("Accept Test Org", @owner, @billing_email)

# Helper to create a fresh invitation
def create_test_invitation(invitee_email, role: 'member')
  Onetime::OrganizationMembership.create_invitation!(
    organization: @org,
    email: invitee_email,
    role: role,
    inviter: @owner,
  )
end

# Helper to create authenticated strategy result for a customer
def auth_result_for(customer)
  MockStrategyResult.authenticated(customer)
end

# Helper to attempt accepting an invitation
# Returns [success_data, error, logic] tuple
def try_accept_invitation(customer, invitation, params = {})
  strategy = auth_result_for(customer)
  default_params = { 'token' => invitation.token }
  logic = InviteAPI::Logic::Invites::AcceptInvite.new(
    strategy,
    default_params.merge(params),
    'en'
  )
  logic.process_params
  logic.raise_concerns
  result = logic.process
  [result, nil, logic]
rescue OT::FormError => e
  [nil, e, nil]
rescue Onetime::Problem => e
  # Model-level errors (from accept!)
  [nil, e, nil]
end

# Helper to test just the raise_concerns phase (logic validation only)
def try_raise_concerns(customer, invitation, params = {})
  strategy = auth_result_for(customer)
  default_params = { 'token' => invitation.token }
  logic = InviteAPI::Logic::Invites::AcceptInvite.new(
    strategy,
    default_params.merge(params),
    'en'
  )
  logic.process_params
  logic.raise_concerns
  [true, nil, logic]
rescue OT::FormError => e
  [false, e, nil]
end

# ============================================================================
# Test: Exact email match - accepts without any special flags
# ============================================================================

## Exact email match - accepts
@exact_email = "exact_match_#{@test_suffix}@test.com"
@exact_user = Onetime::Customer.create!(email: @exact_email)
@exact_invite = create_test_invitation(@exact_email)
@exact_result, @exact_error, @exact_logic = try_accept_invitation(@exact_user, @exact_invite)
@exact_error.nil?
#=> true

## Exact match - returns success data with user_id
@exact_result[:user_id] == @exact_user.extid
#=> true

## Exact match - user is now member of org
@org.member?(@exact_user)
#=> true

## Exact match - invitation status changed to active (reload from Redis)
# After accept!, the UUID-keyed staged model is destroyed. Look up the activated
# composite-keyed membership via org+customer index.
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @exact_user.objid).status
#=> 'active'

# ============================================================================
# Test: Case difference - case-insensitive matching succeeds
# ============================================================================

## Case difference - model uses case-insensitive comparison
@case_email_invited = "CASE_MATCH_#{@test_suffix}@TEST.COM"
@case_email_user = "case_match_#{@test_suffix}@test.com"
@case_user = Onetime::Customer.create!(email: @case_email_user)
@case_invite = create_test_invitation(@case_email_invited)
@case_result, @case_error, _ = try_accept_invitation(@case_user, @case_invite)
@case_error.nil?
#=> true

## Case difference - user is now member of org
@org.member?(@case_user)
#=> true

# ============================================================================
# Test: Different emails - ALWAYS rejects (strict email binding)
# ============================================================================

## Different emails - logic layer rejects
@diff_invited_email = "invited_#{@test_suffix}@company.com"
@diff_user_email = "different_#{@test_suffix}@other.com"
@diff_user = Onetime::Customer.create!(email: @diff_user_email)
@diff_invite = create_test_invitation(@diff_invited_email)
@diff_passed, @diff_error, _ = try_raise_concerns(@diff_user, @diff_invite)
@diff_passed
#=> false

## Different emails rejection - error message mentions mismatch
@diff_error.message.include?('match')
#=> true

## Different emails - error type is email_mismatch (not acknowledgment type)
@diff_error.error_type
#=> 'email_mismatch'

## Different emails - user NOT added to org
@org.member?(@diff_user)
#=> false

# ============================================================================
# Test: acknowledge_email_mismatch param is IGNORED (security change)
# ============================================================================

## Passing acknowledge_email_mismatch=true still fails (param removed)
@ack_invited_email = "ack_invited_#{@test_suffix}@company.com"
@ack_user_email = "ack_different_#{@test_suffix}@other.com"
@ack_user = Onetime::Customer.create!(email: @ack_user_email)
@ack_invite = create_test_invitation(@ack_invited_email)
@ack_passed, @ack_error, _ = try_raise_concerns(
  @ack_user,
  @ack_invite,
  { 'acknowledge_email_mismatch' => true }
)
# Should FAIL - acknowledgment no longer bypasses the check
@ack_passed
#=> false

## String 'true' acknowledgment also fails
@str_invite = create_test_invitation("str_invited_#{@test_suffix}@a.com")
@str_user = Onetime::Customer.create!(email: "str_user_#{@test_suffix}@b.com")
@str_passed, _, _ = try_raise_concerns(
  @str_user,
  @str_invite,
  { 'acknowledge_email_mismatch' => 'true' }
)
# Should FAIL - acknowledgment no longer bypasses the check
@str_passed
#=> false

# ============================================================================
# Test: Plus-tag difference - treated as different email
# ============================================================================

## Plus-tag emails treated as different (no normalization)
@plus_base = "plus_#{@test_suffix}@test.com"
@plus_tagged = "plus_#{@test_suffix}+work@test.com"
@plus_user = Onetime::Customer.create!(email: @plus_base)
@plus_invite = create_test_invitation(@plus_tagged)
@plus_passed, @plus_error, _ = try_raise_concerns(@plus_user, @plus_invite)
# normalize_email only lowercases, doesn't strip +tags
@plus_passed
#=> false

# ============================================================================
# Test: normalize_email behavior via logic instance
# ============================================================================

## normalize_email lowercases the email
@norm_logic = InviteAPI::Logic::Invites::AcceptInvite.allocate
@norm_logic.send(:normalize_email, 'USER@EXAMPLE.COM')
#=> 'user@example.com'

## normalize_email strips whitespace
@norm_logic.send(:normalize_email, '  user@example.com  ')
#=> 'user@example.com'

## normalize_email does NOT strip plus tags (current behavior)
@norm_logic.send(:normalize_email, 'user+tag@example.com')
#=> 'user+tag@example.com'

# ============================================================================
# Test: Error includes specific error_type for frontend handling
# ============================================================================

## Mismatch error has descriptive message
@err_invite = create_test_invitation("err_invited_#{@test_suffix}@a.com")
@err_user = Onetime::Customer.create!(email: "err_user_#{@test_suffix}@b.com")
_, @err_error, _ = try_raise_concerns(@err_user, @err_invite)
@err_error.message
#=> 'Your email address does not match the invitation'

# ============================================================================
# Cleanup
# ============================================================================

[
  @org, @owner, @exact_user, @case_user, @diff_user, @ack_user, @str_user,
  @plus_user, @err_user
].compact.each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.exists?
rescue StandardError
  nil
end
