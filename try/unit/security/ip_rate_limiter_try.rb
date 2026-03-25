# try/unit/security/ip_rate_limiter_try.rb
#
# frozen_string_literal: true

# These tryouts test the IPRateLimiter module functionality.
# The IPRateLimiter prevents abuse via per-IP rate limiting using Redis.
#
# We're testing:
# 1. Recording requests per IP
# 2. Checking rate limits
# 3. LimitExceeded after max requests
# 4. Different events are tracked separately

require_relative '../../support/test_helpers'
require 'onetime/security/ip_rate_limiter'

# Include the module in a test class with mock req object
class IPRateLimiterTester
  include Onetime::Security::IPRateLimiter

  attr_accessor :test_ip

  def client_ip_address
    @test_ip || '127.0.0.1'
  end
end

@tester = IPRateLimiterTester.new
@tester.test_ip = "192.168.1.#{rand(1..254)}"
@test_event = "test_event_#{Familia.now.to_i}"
@other_event = "other_event_#{Familia.now.to_i}"
@other_tester = IPRateLimiterTester.new
@other_tester.test_ip = "10.0.0.#{rand(1..254)}"
@no_ip_tester = IPRateLimiterTester.new
@no_ip_tester.test_ip = ''

# Clean up any existing keys before testing
Familia.dbclient.del("ratelimit:#{@test_event}:#{@tester.test_ip}")

## First request should not raise (count: 1)
begin
  @tester.check_ip_rate_limit!(@test_event, max: 3, window: 60)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## ip_rate_limit_count returns current count
@tester.ip_rate_limit_count(@test_event)
#=> 1

## Second request should not raise (count: 2)
begin
  @tester.check_ip_rate_limit!(@test_event, max: 3, window: 60)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Third request should not raise (count: 3)
begin
  @tester.check_ip_rate_limit!(@test_event, max: 3, window: 60)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Fourth request should raise LimitExceeded (count: 4 > max: 3)
begin
  @tester.check_ip_rate_limit!(@test_event, max: 3, window: 60)
  :no_error
rescue Onetime::LimitExceeded => e
  [e.class.name, e.retry_after.positive?, e.max_attempts]
end
#=> ['Onetime::LimitExceeded', true, 3]

## Different event should have separate counter
begin
  @tester.check_ip_rate_limit!(@other_event, max: 3, window: 60)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Different IP should have separate counter
begin
  @other_tester.check_ip_rate_limit!(@test_event, max: 3, window: 60)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Empty IP should not cause errors (just returns early)
begin
  @no_ip_tester.check_ip_rate_limit!(@test_event, max: 1, window: 60)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## ip_rate_limit_count with empty IP returns 0
@no_ip_tester.ip_rate_limit_count(@test_event)
#=> 0

# Clean up test keys
Familia.dbclient.del("ratelimit:#{@test_event}:#{@tester.test_ip}")
Familia.dbclient.del("ratelimit:#{@other_event}:#{@tester.test_ip}")
Familia.dbclient.del("ratelimit:#{@test_event}:#{@other_tester.test_ip}")
