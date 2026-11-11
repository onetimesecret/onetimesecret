# try/unit/security/feedback_rate_limiter_try.rb
#
# frozen_string_literal: true

# These tryouts test the FeedbackRateLimiter module functionality.
# The FeedbackRateLimiter prevents abuse of the public feedback endpoint
# by tracking submissions per IP and locking out after MAX_SUBMISSIONS.
#
# We're testing:
# 1. Recording submissions
# 2. Checking rate limits
# 3. Lockout after max submissions
# 4. Clearing rate limit
# 5. Blank IP is charged to the shared no-client-ip bucket (otto 2.13 leaves a
#    request with no client IP when the client writes a non-address
#    X-Forwarded-For entry; a no-op would switch the only cap off)

require_relative '../../support/test_models'
require 'onetime/security/feedback_rate_limiter'

OT.boot! :test, true

# Include the module in a test class
class FeedbackRateLimiterTester
  include Onetime::Security::FeedbackRateLimiter
end

@tester  = FeedbackRateLimiterTester.new
@test_ip = "203.0.113.#{rand(1..254)}"

# Get Redis connection via Feedback model's dbclient
@redis = Onetime::Feedback.dbclient

# Clean up any existing keys before testing
@redis.del("feedback:submissions:#{@test_ip}")
@redis.del("feedback:locked:#{@test_ip}")

## First submission should return 1
count = @tester.record_feedback_submission!(@test_ip)
count
#=> 1

## Second submission should return 2
count = @tester.record_feedback_submission!(@test_ip)
count
#=> 2

## check_feedback_rate_limit! should not raise before max
begin
  @tester.check_feedback_rate_limit!(@test_ip)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Submissions 3 through 9 increment the counter
counts = (3..9).map { @tester.record_feedback_submission!(@test_ip) }
counts
#=> [3, 4, 5, 6, 7, 8, 9]

## 10th submission (MAX) returns 10 and creates lockout
count = @tester.record_feedback_submission!(@test_ip)
[count, @redis.exists?("feedback:locked:#{@test_ip}")]
#=> [10, true]

## Submissions counter is cleared after lockout
@redis.exists?("feedback:submissions:#{@test_ip}")
#=> false

## check_feedback_rate_limit! raises LimitExceeded when locked
begin
  @tester.check_feedback_rate_limit!(@test_ip)
  :no_error
rescue Onetime::LimitExceeded => e
  [e.class.name, e.retry_after.positive?, e.max_attempts, e.error_key]
end
#=> ['Onetime::LimitExceeded', true, 10, 'api.feedback.errors.rate_limit_exceeded']

## clear_feedback_rate_limit! removes lockout
@tester.clear_feedback_rate_limit!(@test_ip)
@redis.exists?("feedback:locked:#{@test_ip}")
#=> false

## After clearing, check_feedback_rate_limit! does not raise
begin
  @tester.check_feedback_rate_limit!(@test_ip)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## Empty and nil IPs are charged to the shared no-client-ip bucket, not dropped
@bucket = Onetime::Security::NoClientIp::BUCKET
@redis.del("feedback:submissions:#{@bucket}", "feedback:locked:#{@bucket}")
[@tester.record_feedback_submission!(''), @tester.record_feedback_submission!(nil)]
#=> [1, 2]

## The bucket is a real subject: under the cap a blank IP passes the check
begin
  @tester.check_feedback_rate_limit!(nil)
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :no_error

## ...and at MAX_SUBMISSIONS it locks like any IP, so the next blank-IP
## submission is denied
(Onetime::Security::FeedbackRateLimiter::MAX_SUBMISSIONS - 2).times { @tester.record_feedback_submission!(nil) }
begin
  @tester.check_feedback_rate_limit!('')
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :limit_exceeded

## Clearing with a blank IP clears the shared bucket
@tester.clear_feedback_rate_limit!(nil)
[@redis.exists?("feedback:locked:#{@bucket}"), @redis.exists?("feedback:submissions:#{@bucket}")]
#=> [false, false]

## Independent IPs have independent counters
@other_ip = "198.51.100.#{rand(1..254)}"
@redis.del("feedback:submissions:#{@other_ip}", "feedback:locked:#{@other_ip}")
@tester.record_feedback_submission!(@test_ip)
@tester.record_feedback_submission!(@other_ip)
first  = @redis.get("feedback:submissions:#{@test_ip}").to_i
second = @redis.get("feedback:submissions:#{@other_ip}").to_i
[first, second]
#=> [1, 1]

# Clean up test keys
@redis.del("feedback:submissions:#{@test_ip}")
@redis.del("feedback:locked:#{@test_ip}")
@redis.del("feedback:submissions:#{@other_ip}")
@redis.del("feedback:locked:#{@other_ip}")
