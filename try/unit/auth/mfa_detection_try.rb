# try/unit/auth/mfa_detection_try.rb
#
# frozen_string_literal: true

# These tests cover the MFA detection operation which has been refactored
# to accept only primitive inputs (no Rodauth, no session objects).
#
# We test:
# 1. DetectMfaRequirement operation with various MFA configurations
# 2. Decision object methods and derived properties
# 3. Input validation
# 4. MFA policy overrides
#
# NOTE: This operation is now a PURE FUNCTION with no external dependencies.
# MFA state checking is done by Auth::Operations::MfaStateChecker (tested separately).

require_relative '../../support/test_helpers'

# Load the app with test configuration
OT.boot! :test, false

# Require the auth operations and database
require_relative '../../../apps/web/auth/database'
require_relative '../../../apps/web/auth/operations'

# Setup test data
@account_id = 12345

# =============================================================================
# Test DetectMfaRequirement Operation - No MFA Configured
# =============================================================================

## Test detection when no MFA is configured
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: false,
  has_recovery_codes: false
)
[
  decision.requires_mfa?,
  decision.defer_session_sync?,
  decision.sync_session_now?,
  decision.mfa_methods,
  decision.reason
]
#=> [false, false, true, [], 'no_mfa_configured']

# =============================================================================
# Test DetectMfaRequirement Operation - OTP Only
# =============================================================================

## Test detection when only OTP is configured
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: true,
  has_recovery_codes: false
)
[
  decision.requires_mfa?,
  decision.defer_session_sync?,
  decision.sync_session_now?,
  decision.mfa_methods,
  decision.has_otp?,
  decision.has_recovery_codes?,
  decision.primary_method,
  decision.reason
]
#=> [true, true, false, [:otp], true, false, :otp, 'otp_configured']

# =============================================================================
# Test DetectMfaRequirement Operation - Recovery Codes Only
# =============================================================================

## Test detection when only recovery codes exist (orphaned - should NOT require MFA)
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: false,
  has_recovery_codes: true
)
[
  decision.requires_mfa?,
  decision.mfa_methods,
  decision.has_otp?,
  decision.has_recovery_codes?,
  decision.primary_method,
  decision.reason
]
#=> [false, [:recovery_codes], false, true, :recovery_codes, 'no_mfa_configured']

# =============================================================================
# Test DetectMfaRequirement Operation - Both OTP and Recovery
# =============================================================================

## Test detection when both OTP and recovery codes exist
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: true,
  has_recovery_codes: true
)
[
  decision.requires_mfa?,
  decision.mfa_methods.sort,
  decision.has_otp?,
  decision.has_recovery_codes?,
  decision.primary_method,
  decision.reason
]
#=> [true, [:otp, :recovery_codes], true, true, :otp, 'otp_and_recovery_configured']

# =============================================================================
# Test DetectMfaRequirement - Decision Object Immutability
# =============================================================================

## Test that decision object is immutable
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: true,
  has_recovery_codes: true
)
[
  decision.frozen?,
  decision.mfa_methods.frozen?
]
#=> [true, true]

# =============================================================================
# Test DetectMfaRequirement - MFA Policy Override: Required
# =============================================================================

## Test policy override requiring MFA even without configuration
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: false,
  has_recovery_codes: false,
  mfa_policy: :required
)
[
  decision.requires_mfa?,
  decision.reason
]
#=> [true, 'policy_required']

# =============================================================================
# Test DetectMfaRequirement - MFA Policy Override: Disabled
# =============================================================================

## Test policy override disabling MFA even with configuration
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: @account_id,
  has_otp_secret: true,
  has_recovery_codes: true,
  mfa_policy: :disabled
)
[
  decision.requires_mfa?,
  decision.reason
]
#=> [false, 'policy_disabled']

# =============================================================================
# Test DetectMfaRequirement - Input Validation: Missing account_id
# =============================================================================

## Test that missing account_id raises error
begin
  Auth::Operations::DetectMfaRequirement.call(
    account_id: nil,
    has_otp_secret: false,
    has_recovery_codes: false
  )
  false
rescue Auth::Operations::DetectMfaRequirement::InvalidInput => e
  e.message.include?("account_id")
end
#=> true

# =============================================================================
# Test DetectMfaRequirement - Input Validation: Invalid has_otp_secret
# =============================================================================

## Test that non-boolean has_otp_secret raises error
begin
  Auth::Operations::DetectMfaRequirement.call(
    account_id: @account_id,
    has_otp_secret: "yes",
    has_recovery_codes: false
  )
  false
rescue Auth::Operations::DetectMfaRequirement::InvalidInput => e
  e.message.include?("has_otp_secret")
end
#=> true

# =============================================================================
# Test DetectMfaRequirement - Input Validation: Invalid mfa_policy
# =============================================================================

## Test that invalid mfa_policy raises error
begin
  Auth::Operations::DetectMfaRequirement.call(
    account_id: @account_id,
    has_otp_secret: false,
    has_recovery_codes: false,
    mfa_policy: :invalid
  )
  false
rescue Auth::Operations::DetectMfaRequirement::InvalidInput => e
  e.message.include?("mfa_policy")
end
#=> true

# =============================================================================
# Test DetectMfaRequirement - Account ID String to Integer Conversion
# =============================================================================

## Test that string account_id is converted to integer
decision = Auth::Operations::DetectMfaRequirement.call(
  account_id: "12345",
  has_otp_secret: false,
  has_recovery_codes: false
)
[
  decision.account_id,
  decision.account_id.class
]
#=> [12345, Integer]
