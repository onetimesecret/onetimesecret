# try/unit/auth/mfa_state_checker_try.rb
#
# frozen_string_literal: true

# These tests cover the MfaStateChecker service which queries the database
# for MFA configuration state without depending on Rodauth internals.
#
# We test:
# 1. MfaStateChecker querying database for OTP secrets
# 2. MfaStateChecker querying database for recovery codes
# 3. State object methods and derived properties
# 4. Cache behavior (if enabled)

require_relative '../../support/test_helpers'

# Load the app with test configuration
OT.boot! :test, false

# Require the auth services and database
require_relative '../../../apps/web/auth/database'
require_relative '../../../apps/web/auth/operations/mfa_state_checker'

# =============================================================================
# Setup Test Database
# =============================================================================

# Get database connection (requires advanced mode)
@db = Auth::Database.connection

# Skip tests if database is not available (basic mode)
if @db.nil?
  puts "Skipping MfaStateChecker tests - database not available in basic mode"
  exit 0
end

# Setup test account
@test_account_id = 99999
@db[:account_otp_keys].where(id: @test_account_id).delete
@db[:account_recovery_codes].where(id: @test_account_id).delete

# Create test account if it doesn't exist (required for FK constraints)
unless @db[:accounts].where(id: @test_account_id).count > 0
  @db[:accounts].insert(
    id: @test_account_id,
    email: 'test_mfa_checker@example.com',
    status_id: 2  # Verified status
  )
end

# =============================================================================
# Test MfaStateChecker - No MFA Configured
# =============================================================================

## Test state when no MFA is configured
checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
[
  state.has_otp_secret,
  state.has_recovery_codes,
  state.mfa_enabled?,
  state.available_methods,
  state.reason
]
#=> [false, false, false, [], 'no_mfa_configured']

# =============================================================================
# Test MfaStateChecker - OTP Only
# =============================================================================

## Test state when only OTP is configured
# Note: last_use has DEFAULT CURRENT_TIMESTAMP, so we can't set it to nil
# We'll let it use the default timestamp
@db[:account_otp_keys].insert(
  id: @test_account_id,
  key: 'test_otp_secret_identifier_base32',
  num_failures: 0
)

checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
[
  state.has_otp_secret,
  state.has_recovery_codes,
  state.mfa_enabled?,
  state.available_methods,
  state.reason
]
#=> [true, false, true, [:otp], 'otp_configured']

# =============================================================================
# Test MfaStateChecker - Recovery Codes Only
# =============================================================================

## Test state when only recovery codes exist
# Clean OTP first
@db[:account_otp_keys].where(id: @test_account_id).delete

# Add recovery codes
# Note: account_recovery_codes has composite PK (id, code) where id is FK to accounts
@db[:account_recovery_codes].insert(
  id: @test_account_id,
  code: 'recovery_code_1_hashed'
)
@db[:account_recovery_codes].insert(
  id: @test_account_id,
  code: 'recovery_code_2_hashed'
)

checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
[
  state.has_otp_secret,
  state.has_recovery_codes,
  state.mfa_enabled?,
  state.available_methods,
  state.unused_recovery_code_count,
  state.reason
]
#=> [false, true, true, [:recovery_codes], 2, 'recovery_codes_only']

# =============================================================================
# Test MfaStateChecker - Both OTP and Recovery Codes
# =============================================================================

## Test state when both OTP and recovery codes exist
@db[:account_otp_keys].insert(
  id: @test_account_id,
  key: 'test_otp_secret_identifier_base32',
  num_failures: 0
)

checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
[
  state.has_otp_secret,
  state.has_recovery_codes,
  state.mfa_enabled?,
  state.available_methods.sort,
  state.unused_recovery_code_count,
  state.reason
]
#=> [true, true, true, [:otp, :recovery_codes], 2, 'otp_and_recovery_configured']

# =============================================================================
# Test MfaStateChecker - Used Recovery Codes Ignored
# =============================================================================

## Test that used recovery codes don't count
# Delete one code (simulating it being used - codes are deleted when used, not marked)
@db[:account_recovery_codes]
  .where(id: @test_account_id, code: 'recovery_code_1_hashed')
  .delete

checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
[
  state.has_recovery_codes,
  state.unused_recovery_code_count
]
#=> [true, 1]

# =============================================================================
# Test MfaStateChecker - All Recovery Codes Used
# =============================================================================

## Test state when all recovery codes are used
# Delete all remaining codes
@db[:account_recovery_codes]
  .where(id: @test_account_id)
  .delete

checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
[
  state.has_otp_secret,
  state.has_recovery_codes,
  state.mfa_enabled?,
  state.available_methods,
  state.unused_recovery_code_count,
  state.reason
]
#=> [true, false, true, [:otp], 0, 'otp_configured']

# =============================================================================
# Test MfaStateChecker - State Object Immutability
# =============================================================================

## Test that State object is immutable
checker = Auth::Operations::MfaStateChecker.new(@db)
state = checker.check(@test_account_id)
state.frozen?
#=> true

## Test that available_methods array is frozen
# Need to recreate state since tryouts test cases are isolated
checker2 = Auth::Operations::MfaStateChecker.new(@db)
state2 = checker2.check(@test_account_id)
state2.available_methods.frozen?
#=> true

# =============================================================================
# Test MfaStateChecker - Cache Behavior
# =============================================================================

## Test cache hit after initial query
checker_with_cache = Auth::Operations::MfaStateChecker.new(@db, cache_ttl: 60)

# First call queries database
state1 = checker_with_cache.check(@test_account_id)

# Second call should hit cache (we can't easily verify this without instrumentation,
# but we can verify the result is consistent)
state2 = checker_with_cache.check(@test_account_id)

[
  state1.has_otp_secret == state2.has_otp_secret,
  state1.has_recovery_codes == state2.has_recovery_codes,
  state1.account_id == state2.account_id
]
#=> [true, true, true]

# =============================================================================
# Test MfaStateChecker - Clear Cache
# =============================================================================

## Test clearing cache for specific account
# Recreate checker with cache since tryouts test cases are isolated
checker_with_cache2 = Auth::Operations::MfaStateChecker.new(@db, cache_ttl: 60)
first_check = checker_with_cache2.check(@test_account_id)
checker_with_cache2.clear_cache(@test_account_id)
# After clearing, next check should query database again
second_check = checker_with_cache2.check(@test_account_id)
second_check.account_id
#=> 99999

# =============================================================================
# Cleanup Test Data
# =============================================================================

## Clean up test data from database
@db[:account_otp_keys].where(id: @test_account_id).delete
@db[:account_recovery_codes].where(id: @test_account_id).delete
@db[:accounts].where(id: @test_account_id).delete
true
#=> true
