# try/unit/security/passphrase_rate_limiter_try.rb
#
# frozen_string_literal: true

# These tryouts test the PassphraseRateLimiter module functionality.
# The PassphraseRateLimiter prevents brute-force attacks on secret passphrases
# by tracking failed attempts and locking out after MAX_ATTEMPTS.
#
# We're testing:
# 1. Recording failed attempts
# 2. Checking rate limits
# 3. Lockout after max attempts
# 4. Clearing rate limit on success

require_relative '../../support/test_models'
require 'onetime/security/passphrase_rate_limiter'

OT.boot! :test, true

# Include the module in a test class
class PassphraseRateLimiterTester
  include Onetime::Security::PassphraseRateLimiter
end

@tester = PassphraseRateLimiterTester.new
@test_secret_id = "test_secret_#{Familia.now.to_i}_#{rand(10000)}"

# Get Redis connection via model's dbclient
@redis = Onetime::Secret.dbclient

# Clean up any existing keys before testing
@redis.del("passphrase:attempts:#{@test_secret_id}")
@redis.del("passphrase:locked:#{@test_secret_id}")

## First attempt should return 1
attempt_count = @tester.record_failed_passphrase_attempt!(@test_secret_id)
attempt_count
#=> 1

## Second attempt should return 2
attempt_count = @tester.record_failed_passphrase_attempt!(@test_secret_id)
attempt_count
#=> 2

## check_passphrase_rate_limit! should not raise before max attempts
begin
  @tester.check_passphrase_rate_limit!(@test_secret_id)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Third attempt should return 3
attempt_count = @tester.record_failed_passphrase_attempt!(@test_secret_id)
attempt_count
#=> 3

## Fourth attempt should return 4
attempt_count = @tester.record_failed_passphrase_attempt!(@test_secret_id)
attempt_count
#=> 4

## Fifth attempt (MAX) should return 5 and create lockout
attempt_count = @tester.record_failed_passphrase_attempt!(@test_secret_id)
[attempt_count, @redis.exists?("passphrase:locked:#{@test_secret_id}")]
#=> [5, true]

## Attempts counter should be cleared after lockout
@redis.exists?("passphrase:attempts:#{@test_secret_id}")
#=> false

## check_passphrase_rate_limit! should raise LimitExceeded when locked
begin
  @tester.check_passphrase_rate_limit!(@test_secret_id)
  :no_error
rescue Onetime::LimitExceeded => e
  [e.class.name, e.retry_after.positive?, e.max_attempts]
end
#=> ['Onetime::LimitExceeded', true, 5]

## clear_passphrase_rate_limit! should remove lockout
@tester.clear_passphrase_rate_limit!(@test_secret_id)
@redis.exists?("passphrase:locked:#{@test_secret_id}")
#=> false

## After clearing, check_passphrase_rate_limit! should not raise
begin
  @tester.check_passphrase_rate_limit!(@test_secret_id)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Empty identifier should not cause errors
@tester.record_failed_passphrase_attempt!('')
#=> 0

## Nil identifier should not cause errors
@tester.record_failed_passphrase_attempt!(nil)
#=> 0

# Clean up test keys
@redis.del("passphrase:attempts:#{@test_secret_id}")
@redis.del("passphrase:locked:#{@test_secret_id}")
