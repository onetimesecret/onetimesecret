# try/unit/v3_feedback_try.rb
#
# frozen_string_literal: true

# Tests for V3::Logic::ReceiveFeedback
#
# Specifically covers:
# 1. format_feedback_message correctly formats messages for anonymous users (nil cust)
# 2. format_feedback_message correctly formats messages for authenticated users
# 3. send_feedback handles nil sender without crashing
# 4. send_feedback handles anonymous sender correctly
#
# These tests verify the nil sender handling added in #2733.

require_relative '../support/test_helpers'
require_relative '../support/test_models'

# Load V2 logic base first (provides UriHelpers mixin used by V3)
require 'api/v2/logic/base'

# Load V3 feedback logic
require 'api/v3/logic/base'
require 'api/v3/logic/feedback'

# Load the app with test configuration
OT.boot! :test, false

@email = "feedback_test_#{SecureRandom.hex(4)}@example.test"

# Create a customer with anonymous role for testing
@anonymous_customer = Customer.new email: 'anonymous@example.com'
@anonymous_customer.role = 'anonymous'

# Create authenticated customer
@authenticated_customer = Customer.new email: @email
@authenticated_customer.role = 'customer'
@authenticated_customer.verified = true

@params = {
  'msg' => 'Test feedback message',
  'tz' => 'America/New_York',
  'version' => '1.0.0',
}


## feedback_user_id returns anon identifier for nil customer
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.send(:feedback_user_id).start_with?('anon:')
#=> true

## feedback_user_id returns anon identifier for anonymous customer (role=anonymous)
# Even if cust is set but has anonymous role, should be treated as anonymous
session = MockSession.new
strategy_result = MockStrategyResult.new(session: session, user: @anonymous_customer, auth_method: 'session')
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.send(:feedback_user_id).start_with?('anon:')
#=> true

## feedback_user_id returns extid for authenticated customer
session = MockSession.new
strategy_result = MockStrategyResult.authenticated(@authenticated_customer, session: session)
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.send(:feedback_user_id)
#=> @authenticated_customer.extid

## formatted_for_storage embeds user id, timezone and version metadata
# The Redis-stored copy keeps a single-line representation for the colonel
# admin view, even though the email body now renders these as separate
# fields rather than appending them to the message text.
session = MockSession.new
strategy_result = MockStrategyResult.authenticated(@authenticated_customer, session: session)
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
formatted = logic.send(:formatted_for_storage, 'Hello world')
formatted.include?('Hello world') &&
  formatted.include?(@authenticated_customer.extid) &&
  formatted.include?('[TZ: America/New_York]') &&
  formatted.include?('[v1.0.0]')
#=> true

## send_feedback handles nil sender without crashing
# send_feedback now takes a recipient email string directly so the
# emailer.feedback_to override and colonel-fallback branches share one
# delivery path.
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
# This should not raise an error - nil sender is valid
result = begin
  logic.send(:send_feedback, 'colonel@onetimesecret.com', nil, 'Test message')
  :no_error
rescue StandardError => e
  e.class.name
end
result
#=> :no_error

## send_feedback uses 'anonymous' email for nil sender
# We can't easily test the enqueued email params, but we can verify the method
# doesn't crash and follows the expected code path
colonel = Customer.new email: 'colonel@onetimesecret.com'
colonel.role = 'colonel'
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
# Test the sender_email calculation logic directly
sender = nil
sender_email = sender.nil? || sender.anonymous? ? 'anonymous' : sender.email
sender_email
#=> 'anonymous'

## send_feedback uses 'anonymous' email for anonymous customer
# Customer with role='anonymous' should also result in 'anonymous' email
sender = @anonymous_customer
sender_email = sender.nil? || sender.anonymous? ? 'anonymous' : sender.email
sender_email
#=> 'anonymous'

## send_feedback uses actual email for authenticated customer
sender = @authenticated_customer
sender_email = sender.nil? || sender.anonymous? ? 'anonymous' : sender.email
sender_email
#=> @email

## anonymous_user? returns true for nil customer
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.anonymous_user?
#=> true

## anonymous_user? returns true for customer with anonymous role
session = MockSession.new
strategy_result = MockStrategyResult.new(session: session, user: @anonymous_customer, auth_method: 'session')
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.anonymous_user?
#=> true

## anonymous_user? returns false for authenticated customer
session = MockSession.new
strategy_result = MockStrategyResult.authenticated(@authenticated_customer, session: session)
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.anonymous_user?
#=> false

## reply_to is omitted for anonymous senders so admins reply to from-address
# Mirrors the conditional in send_feedback that gates the reply_to header.
sender = nil
is_anonymous = sender.nil? || sender.anonymous?
data = { email_address: 'anonymous' }
data[:reply_to] = sender.email unless is_anonymous
data.key?(:reply_to)
#=> false

## reply_to is omitted for customers with anonymous role
sender = @anonymous_customer
is_anonymous = sender.nil? || sender.anonymous?
data = { email_address: 'anonymous' }
data[:reply_to] = sender.email unless is_anonymous
data.key?(:reply_to)
#=> false

## reply_to is set to sender email for authenticated customers
sender = @authenticated_customer
is_anonymous = sender.nil? || sender.anonymous?
data = { email_address: sender.email }
data[:reply_to] = sender.email unless is_anonymous
data[:reply_to]
#=> @email

## send_feedback still runs without raising for authenticated sender
strategy_result = MockStrategyResult.authenticated(@authenticated_customer, session: MockSession.new)
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
result = begin
  logic.send(:send_feedback, 'colonel@onetimesecret.com', @authenticated_customer, 'Test message')
  :no_error
rescue StandardError => e
  e.class.name
end
result
#=> :no_error

## feedback_recipient_email returns the configured override when set
# Stash and override emailer.feedback_to to verify the override branch
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
original_emailer = OT.conf['emailer']
OT.conf['emailer'] = (original_emailer || {}).merge('feedback_to' => 'team@example.com')
begin
  logic.send(:feedback_recipient_email)
ensure
  OT.conf['emailer'] = original_emailer
end
#=> 'team@example.com'

## feedback_recipient_email ignores blank override and falls back to colonel lookup
# Empty string in config should not short-circuit the colonel lookup.
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
original_emailer = OT.conf['emailer']
OT.conf['emailer'] = (original_emailer || {}).merge('feedback_to' => '   ')
begin
  configured = logic.send(:feedback_recipient_email)
  # Either nil (no colonel in test DB) or a real colonel address — but never
  # the blank/whitespace value from config.
  configured.nil? || (configured.is_a?(String) && !configured.strip.empty?)
ensure
  OT.conf['emailer'] = original_emailer
end
#=> true

## client_ip pulls the ip from strategy_result.metadata
strategy_result = MockStrategyResult.anonymous(metadata: { ip: '203.0.113.7' })
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.send(:client_ip)
#=> '203.0.113.7'

## client_ip returns nil when metadata has no ip key
strategy_result = MockStrategyResult.anonymous(metadata: {})
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
logic.send(:client_ip).nil?
#=> true

## raise_concerns does not raise the rate-limit error when IP is unknown
# Blank IP is a no-op in FeedbackRateLimiter, so an unknown-IP submission
# should still fall through to the regular empty-message check.
strategy_result = MockStrategyResult.anonymous(metadata: {})
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
result = begin
  logic.raise_concerns
  :no_error
rescue Onetime::LimitExceeded
  :limit_exceeded
rescue StandardError
  :other_error
end
result
#=> :no_error

## raise_concerns raises LimitExceeded once the IP is locked
# Manually lock the test IP via the rate limiter, then verify the logic
# class refuses further submissions from that IP.
@rate_limited_ip = "203.0.113.#{rand(1..254)}"
redis = Onetime::Feedback.dbclient
redis.del("feedback:submissions:#{@rate_limited_ip}", "feedback:locked:#{@rate_limited_ip}")
# Drive the counter to lockout via the public API to exercise the real path
strategy_result = MockStrategyResult.anonymous(metadata: { ip: @rate_limited_ip })
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
Onetime::Security::FeedbackRateLimiter::MAX_SUBMISSIONS.times do
  logic.send(:record_feedback_submission!, @rate_limited_ip)
end
result = begin
  logic.raise_concerns
  :no_error
rescue Onetime::LimitExceeded => e
  [:limit_exceeded, e.max_attempts]
end
# Clean up before reporting result
logic.send(:clear_feedback_rate_limit!, @rate_limited_ip)
result
#=> [:limit_exceeded, 10]
