# try/unit/security/invite_token_rate_limiter_try.rb
#
# frozen_string_literal: true

# These tryouts test the InviteTokenRateLimiter class functionality.
# The InviteTokenRateLimiter prevents token enumeration attacks on invite
# endpoints by tracking request attempts per IP and locking out after MAX_ATTEMPTS.
#
# We're testing:
# 1. First 10 requests succeed
# 2. 11th request raises LimitExceeded
# 3. Different IPs have independent limits
# 4. Counter resets after window expires (simulated via reset!)
# 5. reset! clears the counter and lockout

require_relative '../../support/test_models'
require 'onetime/security/invite_token_rate_limiter'

OT.boot! :test, true

@test_ip = "192.168.1.#{rand(100..199)}"
@test_ip2 = "10.0.0.#{rand(100..199)}"
@redis = Onetime::Secret.dbclient

# Clean up any existing keys before testing
@redis.del("invite_attempts:#{@test_ip}")
@redis.del("invite_locked:#{@test_ip}")
@redis.del("invite_attempts:#{@test_ip2}")
@redis.del("invite_locked:#{@test_ip2}")

## New limiter should not be rate limited
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
limiter.rate_limited?
#=> false

## New limiter should have MAX_ATTEMPTS remaining
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
limiter.attempts_remaining
#=> 10

## check! should not raise on fresh IP
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
begin
  limiter.check!
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## First attempt should return attempts: 1, locked: false
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
result = limiter.record_attempt
[result[:attempts], result[:locked]]
#=> [1, false]

## After 1 attempt, 9 attempts remaining
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
limiter.attempts_remaining
#=> 9

## Recording attempts 2-9 should not lock
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
8.times { limiter.record_attempt }
result = limiter.record_attempt  # 10th attempt
[result[:attempts], result[:locked], limiter.rate_limited?]
#=> [10, true, true]

## After lockout, check! should raise LimitExceeded
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
begin
  limiter.check!
  :no_error
rescue Onetime::LimitExceeded => e
  [e.class.name, e.retry_after.positive?, e.max_attempts]
end
#=> ['Onetime::LimitExceeded', true, 10]

## After lockout, attempts_remaining should be 0
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
limiter.attempts_remaining
#=> 0

## Different IP should have independent limit (not locked)
limiter2 = Onetime::Security::InviteTokenRateLimiter.new(@test_ip2)
limiter2.rate_limited?
#=> false

## Different IP should have full attempts remaining
limiter2 = Onetime::Security::InviteTokenRateLimiter.new(@test_ip2)
limiter2.attempts_remaining
#=> 10

## Different IP check! should not raise
limiter2 = Onetime::Security::InviteTokenRateLimiter.new(@test_ip2)
begin
  limiter2.check!
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## reset! should clear lockout
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
limiter.reset!
limiter.rate_limited?
#=> false

## After reset!, check! should not raise
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
begin
  limiter.check!
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## After reset!, attempts_remaining should be MAX_ATTEMPTS
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ip)
limiter.attempts_remaining
#=> 10

## Empty IP should not cause errors
limiter = Onetime::Security::InviteTokenRateLimiter.new('')
result = limiter.record_attempt
result[:attempts]
#=> 0

## Nil IP should not cause errors
limiter = Onetime::Security::InviteTokenRateLimiter.new(nil)
result = limiter.record_attempt
result[:attempts]
#=> 0

## IPv6 address should work correctly
@test_ipv6 = "2001:db8:#{rand(1000..9999)}::1"
@redis.del("invite_attempts:#{@test_ipv6}")
@redis.del("invite_locked:#{@test_ipv6}")
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ipv6)
result = limiter.record_attempt
[result[:attempts], result[:locked]]
#=> [1, false]

# Clean up test keys
@redis.del("invite_attempts:#{@test_ip}")
@redis.del("invite_locked:#{@test_ip}")
@redis.del("invite_attempts:#{@test_ip2}")
@redis.del("invite_locked:#{@test_ip2}")
@redis.del("invite_attempts:#{@test_ipv6}")
@redis.del("invite_locked:#{@test_ipv6}")
