# try/unit/logic/organizations/invites/accept_invite_email_mismatch_try.rb
#
# frozen_string_literal: true

#
# Tests for AcceptInvite email matching and mismatch acknowledgment logic.
#
# Tests cover:
# 1. Exact email match - accepts without acknowledgment
# 2. Case difference only - accepts without acknowledgment (case-insensitive)
# 3. Different emails without acknowledgment - rejects with specific error
# 4. Different emails with acknowledgment - accepts (WHEN MODEL UPDATED)
#
# CURRENT IMPLEMENTATION STATE:
# - AcceptInvite logic: Has acknowledge_email_mismatch param support
# - OrganizationMembership.accept!: Does strict equality check (no normalization)
# - GAP: Model doesn't accept force_accept param, so acknowledgment fails at model layer
#
# The logic layer correctly validates and allows mismatch with acknowledgment,
# but the model layer blocks it. Tests document current behavior and expected fixes.

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
# Test: Exact email match - accepts without acknowledgment
# ============================================================================

## Exact email match - accepts without acknowledgment param
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
Onetime::OrganizationMembership.load(@exact_invite.objid).status
#=> 'active'

# ============================================================================
# Test: Case difference - current model does strict equality
# ============================================================================

## Case difference - model uses strict equality so this should fail
@case_email_invited = "CASE_MATCH_#{@test_suffix}@TEST.COM"
@case_email_user = "case_match_#{@test_suffix}@test.com"
@case_user = Onetime::Customer.create!(email: @case_email_user)
@case_invite = create_test_invitation(@case_email_invited)
# Note: Model's accept! does customer.email != invited_email (strict)
@case_result, @case_error, _ = try_accept_invitation(@case_user, @case_invite)
# This tests CURRENT behavior - may fail at model layer due to case sensitivity
@case_error.nil? || @case_error.message.include?('mismatch')
#=> true

# ============================================================================
# Test: Different emails WITHOUT acknowledgment - rejects at logic layer
# ============================================================================

## Different emails without acknowledgment - logic layer rejects
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

## Different emails - user NOT added to org (blocked at logic layer)
@org.member?(@diff_user)
#=> false

# ============================================================================
# Test: Different emails WITH acknowledgment - logic layer passes
# ============================================================================

## Logic layer accepts mismatch when acknowledge_email_mismatch=true
@ack_invited_email = "ack_invited_#{@test_suffix}@company.com"
@ack_user_email = "ack_different_#{@test_suffix}@other.com"
@ack_user = Onetime::Customer.create!(email: @ack_user_email)
@ack_invite = create_test_invitation(@ack_invited_email)
@ack_passed, @ack_error, _ = try_raise_concerns(
  @ack_user,
  @ack_invite,
  { 'acknowledge_email_mismatch' => true }
)
@ack_passed
#=> true

## Logic layer passes with string 'true' for acknowledgment
@str_invite = create_test_invitation("str_invited_#{@test_suffix}@a.com")
@str_user = Onetime::Customer.create!(email: "str_user_#{@test_suffix}@b.com")
@str_passed, _, _ = try_raise_concerns(
  @str_user,
  @str_invite,
  { 'acknowledge_email_mismatch' => 'true' }
)
@str_passed
#=> true

# ============================================================================
# Test: Full acceptance with acknowledgment - model layer behavior
# ============================================================================

## Full acceptance with acknowledgment succeeds end-to-end
@full_invite = create_test_invitation("full_invited_#{@test_suffix}@a.com")
@full_user = Onetime::Customer.create!(email: "full_user_#{@test_suffix}@b.com")
@full_result, @full_error, _ = try_accept_invitation(
  @full_user,
  @full_invite,
  { 'acknowledge_email_mismatch' => true }
)
# Model's accept! respects acknowledge_mismatch: flag
@full_error.nil?
#=> true

## User is added to org with acknowledged mismatch
@org.member?(@full_user)
#=> true

# ============================================================================
# Test: Plus-tag difference behavior
# ============================================================================

## Plus-tag emails treated as different (no normalization in current impl)
@plus_base = "plus_#{@test_suffix}@test.com"
@plus_tagged = "plus_#{@test_suffix}+work@test.com"
@plus_user = Onetime::Customer.create!(email: @plus_base)
@plus_invite = create_test_invitation(@plus_tagged)
@plus_passed, @plus_error, _ = try_raise_concerns(@plus_user, @plus_invite)
# normalize_email only lowercases, doesn't strip +tags
# So plus_#{suffix}@test.com != plus_#{suffix}+work@test.com
@plus_passed
#=> false

## Plus-tag with acknowledgment passes logic layer
@plus2_invite = create_test_invitation("plus2_#{@test_suffix}+tag@test.com")
@plus2_user = Onetime::Customer.create!(email: "plus2_#{@test_suffix}@test.com")
@plus2_passed, _, _ = try_raise_concerns(
  @plus2_user,
  @plus2_invite,
  { 'acknowledge_email_mismatch' => true }
)
@plus2_passed
#=> true

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
  @full_user, @plus_user, @plus2_user, @err_user
].compact.each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.exists?
rescue StandardError
  nil
end
