# try/unit/security/dns_rate_limiter_try.rb
#
# frozen_string_literal: true

# These tryouts test the DnsRateLimiter module functionality.
# The DnsRateLimiter prevents excessive DNS verification attempts
# by tracking requests per domain in a fixed time window using a key TTL
# (the counter resets when the underlying Redis key expires).
#
# We're testing:
# 1. Rate limit status reporting
# 2. Incrementing verification count
# 3. Rate limit enforcement after max attempts
# 4. Clearing rate limit

require_relative '../../support/test_models'
require 'onetime/security/dns_rate_limiter'

OT.boot! :test, true

# Include the module in a test class
class DnsRateLimiterTester
  include Onetime::Security::DnsRateLimiter
end

@tester = DnsRateLimiterTester.new
@test_domain_id = "test_domain_#{Familia.now.to_i}_#{rand(10000)}"

# Get Redis connection via CustomDomain's dbclient
@redis = Onetime::CustomDomain.dbclient

# Clean up any existing keys before testing
@redis.del("dns:ratelimit:#{@test_domain_id}")

## Initial status shows full quota available
status = @tester.dns_rate_limit_status(@test_domain_id)
[status[:remaining], status[:current], status[:limit]]
#=> [10, 0, 10]

## First check increments counter and returns remaining
status = @tester.check_dns_rate_limit!(@test_domain_id)
[status[:remaining], status[:current], status[:limit]]
#=> [9, 1, 10]

## Status check does not increment counter
status = @tester.dns_rate_limit_status(@test_domain_id)
[status[:remaining], status[:current]]
#=> [9, 1]

## Second through ninth checks decrement remaining
8.times { @tester.check_dns_rate_limit!(@test_domain_id) }
status = @tester.dns_rate_limit_status(@test_domain_id)
[status[:remaining], status[:current]]
#=> [1, 9]

## Tenth check succeeds but leaves no remaining
status = @tester.check_dns_rate_limit!(@test_domain_id)
[status[:remaining], status[:current]]
#=> [0, 10]

## Eleventh check raises LimitExceeded
begin
  @tester.check_dns_rate_limit!(@test_domain_id)
  :no_error
rescue Onetime::LimitExceeded => e
  [e.class.name, e.retry_after.positive?, e.max_attempts]
end
#=> ['Onetime::LimitExceeded', true, 10]

## Status still shows exhausted quota
status = @tester.dns_rate_limit_status(@test_domain_id)
[status[:remaining], status[:current]]
#=> [0, 10]

## Clear rate limit resets quota
@tester.clear_dns_rate_limit!(@test_domain_id)
status = @tester.dns_rate_limit_status(@test_domain_id)
[status[:remaining], status[:current]]
#=> [10, 0]

## After clearing, check succeeds again
status = @tester.check_dns_rate_limit!(@test_domain_id)
[status[:remaining], status[:current]]
#=> [9, 1]

## Empty domain_id returns default status without error
status = @tester.check_dns_rate_limit!('')
[status[:remaining], status[:current], status[:limit]]
#=> [10, 0, 10]

## Nil domain_id returns default status without error
status = @tester.check_dns_rate_limit!(nil)
[status[:remaining], status[:current], status[:limit]]
#=> [10, 0, 10]

# --- Rate limit key sanitization with special characters ---

## Domain ID with colons produces valid Redis key
@special_domain_id = "cd:org:abc123:domain"
@tester.clear_dns_rate_limit!(@special_domain_id)
status = @tester.check_dns_rate_limit!(@special_domain_id)
[status[:remaining], status[:current]]
#=> [9, 1]

## Domain ID with Unicode characters produces valid Redis key
@unicode_domain_id = "cd:unicode_\u00e9\u00f1\u00fc_test"
@tester.clear_dns_rate_limit!(@unicode_domain_id)
status = @tester.check_dns_rate_limit!(@unicode_domain_id)
[status[:remaining], status[:current]]
#=> [9, 1]

## Domain ID with spaces works correctly
@space_domain_id = "cd:domain with spaces"
@tester.clear_dns_rate_limit!(@space_domain_id)
status = @tester.check_dns_rate_limit!(@space_domain_id)
[status[:remaining], status[:current]]
#=> [9, 1]

## Domain ID with newlines is handled safely
@newline_domain_id = "cd:domain\nwith\nnewlines"
@tester.clear_dns_rate_limit!(@newline_domain_id)
status = @tester.check_dns_rate_limit!(@newline_domain_id)
[status[:remaining], status[:current]]
#=> [9, 1]

## Domain ID with Redis special chars produces valid key
@redis_special_id = "cd:test{curly}[bracket]*star"
@tester.clear_dns_rate_limit!(@redis_special_id)
status = @tester.check_dns_rate_limit!(@redis_special_id)
[status[:remaining], status[:current]]
#=> [9, 1]

# Clean up test keys
@redis.del("dns:ratelimit:#{@test_domain_id}")
@redis.del("dns:ratelimit:#{@special_domain_id}")
@redis.del("dns:ratelimit:#{@unicode_domain_id}")
@redis.del("dns:ratelimit:#{@space_domain_id}")
@redis.del("dns:ratelimit:#{@newline_domain_id}")
@redis.del("dns:ratelimit:#{@redis_special_id}")
