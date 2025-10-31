# try/unit/auth/mfa_detection_try.rb

# These tests cover the MFA detection operation which was extracted
# from the login hook to improve testability and maintainability.
#
# We test:
# 1. DetectMfaRequirement operation with various scenarios
# 2. Decision object methods
# 3. Integration with Rodauth methods

require_relative '../../support/test_helpers'

# Load the app with test configuration
OT.boot! :test, false

# Require the auth operations and database
require_relative '../../../apps/web/auth/database'
require_relative '../../../apps/web/auth/operations'

# Mock Rodauth instance for testing
class MockRodauth
  attr_accessor :mfa_enabled

  def initialize(mfa_enabled: false)
    @mfa_enabled = mfa_enabled
    @otp_failures_removed = false
    @otp_key_removed = false
  end

  def uses_two_factor_authentication?
    @mfa_enabled
  end

  def _otp_remove_auth_failures
    @otp_failures_removed = true
  end

  def _otp_remove_key(account_id)
    @otp_key_removed = true
    @account_id = account_id
  end

  def recovery_codes_table
    :account_recovery_codes
  end

  def recovery_codes_id_column
    :account_id
  end

  def respond_to?(method_name, include_private = false)
    [:_otp_remove_auth_failures, :_otp_remove_key, :recovery_codes_table, :recovery_codes_id_column].include?(method_name) || super
  end
end

# Setup test data
@account = {
  id: 12345,
  email: 'test@example.com',
  external_id: 'cust_abc123',
  status_id: 2
}

@account_id = @account[:id]

# =============================================================================
# Test DetectMfaRequirement Operation - No MFA, No Recovery
# =============================================================================

## Test detection when MFA is not enabled
@session = {}
@rodauth = MockRodauth.new(mfa_enabled: false)
decision = Auth::Operations::DetectMfaRequirement.call(
  account: @account,
  session: @session,
  rodauth: @rodauth
)
[
  decision.requires_mfa?,
  decision.defer_session_sync?,
  decision.sync_session_now?
]
#=> [false, false, true]

# =============================================================================
# Test DetectMfaRequirement Operation - MFA Enabled
# =============================================================================

## Test detection when MFA is enabled
@session = {}
@rodauth = MockRodauth.new(mfa_enabled: true)
decision = Auth::Operations::DetectMfaRequirement.call(
  account: @account,
  session: @session,
  rodauth: @rodauth
)
[
  decision.requires_mfa?,
  decision.defer_session_sync?,
  decision.sync_session_now?
]
#=> [true, true, false]

# =============================================================================
# Test DetectMfaRequirement Decision Object - Account Data
# =============================================================================

## Test decision object provides account data
@session = {}
@rodauth = MockRodauth.new(mfa_enabled: false)
decision = Auth::Operations::DetectMfaRequirement.call(
  account: @account,
  session: @session,
  rodauth: @rodauth
)
[
  decision.account_id,
  decision.email,
  decision.external_id
]
#=> [12345, 'test@example.com', 'cust_abc123']

# =============================================================================
# Test DetectMfaRequirement - Edge Case: Nil External ID
# =============================================================================

## Test detection with account missing external_id
@account_no_extid = {
  id: 67890,
  email: 'another@example.com',
  external_id: nil,
  status_id: 2
}
@session = {}
@rodauth = MockRodauth.new(mfa_enabled: false)
decision = Auth::Operations::DetectMfaRequirement.call(
  account: @account_no_extid,
  session: @session,
  rodauth: @rodauth
)
[
  decision.external_id.nil?,
  decision.account_id,
  decision.email
]
#=> [true, 67890, 'another@example.com']
