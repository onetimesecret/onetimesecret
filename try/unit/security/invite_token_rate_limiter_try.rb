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

# Force rate limiter to work in test environment for these unit tests
Onetime::Security::InviteTokenRateLimiter.force_enabled = true

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

# --- IP Validation Tests (using IPAddr) ---

## Valid IPv4 address returns canonical form
@test_ipv4_valid = "192.168.1.100"
@redis.del("invite_attempts:#{@test_ipv4_valid}")
limiter = Onetime::Security::InviteTokenRateLimiter.new(@test_ipv4_valid)
limiter.instance_variable_get(:@ip_address)
#=> "192.168.1.100"

## Valid IPv4 with leading/trailing whitespace is normalized
limiter = Onetime::Security::InviteTokenRateLimiter.new("  10.0.0.1  ")
limiter.instance_variable_get(:@ip_address)
#=> "10.0.0.1"

## Valid IPv6 address returns canonical form
limiter = Onetime::Security::InviteTokenRateLimiter.new("2001:0db8:0000:0000:0000:0000:0000:0001")
limiter.instance_variable_get(:@ip_address)
#=> "2001:db8::1"

## Valid IPv6 compressed form is accepted
limiter = Onetime::Security::InviteTokenRateLimiter.new("::1")
limiter.instance_variable_get(:@ip_address)
#=> "::1"

## Invalid IP address returns empty string
limiter = Onetime::Security::InviteTokenRateLimiter.new("not.an.ip.address")
limiter.instance_variable_get(:@ip_address)
#=> ""

## Malformed IP with extra octets returns empty string
limiter = Onetime::Security::InviteTokenRateLimiter.new("192.168.1.1.1")
limiter.instance_variable_get(:@ip_address)
#=> ""

## IP with injection attempt returns empty string
limiter = Onetime::Security::InviteTokenRateLimiter.new("192.168.1.1; DROP TABLE users")
limiter.instance_variable_get(:@ip_address)
#=> ""

## Nil IP returns empty string (handled gracefully)
limiter = Onetime::Security::InviteTokenRateLimiter.new(nil)
limiter.instance_variable_get(:@ip_address)
#=> ""

## Empty string IP returns empty string
limiter = Onetime::Security::InviteTokenRateLimiter.new("")
limiter.instance_variable_get(:@ip_address)
#=> ""

## Whitespace-only IP returns empty string
limiter = Onetime::Security::InviteTokenRateLimiter.new("   ")
limiter.instance_variable_get(:@ip_address)
#=> ""

# --- TTL Refresh Tests ---

## TTL is set on first attempt
@test_ip_ttl = "192.168.#{rand(1..254)}.#{rand(1..254)}"
@redis.del("invite_attempts:#{@test_ip_ttl}")
@redis.del("invite_locked:#{@test_ip_ttl}")
@limiter_ttl = Onetime::Security::InviteTokenRateLimiter.new(@test_ip_ttl)
@limiter_ttl.record_attempt
ttl_after_first = @redis.ttl("invite_attempts:#{@test_ip_ttl}")
ttl_after_first > 0 && ttl_after_first <= 600
#=> true

## TTL is refreshed on subsequent attempts (not just first)
# Wait a brief moment and record another attempt
sleep(0.1)
@limiter_ttl.record_attempt
ttl_after_second = @redis.ttl("invite_attempts:#{@test_ip_ttl}")
# TTL should be close to WINDOW_SECONDS (600) after refresh
ttl_after_second > 590 && ttl_after_second <= 600
#=> true

## TTL refresh test cleanup
@redis.del("invite_attempts:#{@test_ip_ttl}")
@redis.del("invite_locked:#{@test_ip_ttl}")

# Clean up test keys
@redis.del("invite_attempts:#{@test_ip}")
@redis.del("invite_locked:#{@test_ip}")
@redis.del("invite_attempts:#{@test_ip2}")
@redis.del("invite_locked:#{@test_ip2}")
@redis.del("invite_attempts:#{@test_ipv6}")
@redis.del("invite_locked:#{@test_ipv6}")
