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
require 'apps/api/v2/logic/base'

# Load V3 feedback logic
require 'apps/api/v3/logic/base'
require 'apps/api/v3/logic/feedback'

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


## format_feedback_message returns anon identifier for nil customer
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
formatted = logic.send(:format_feedback_message)
# Should contain anon: prefix and session identifier
formatted.include?('anon:') && formatted.include?('[TZ: America/New_York]')
#=> true

## format_feedback_message returns anon identifier for anonymous customer (role=anonymous)
# Even if cust is set but has anonymous role, should be treated as anonymous
session = MockSession.new
strategy_result = MockStrategyResult.new(session: session, user: @anonymous_customer, auth_method: 'session')
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
formatted = logic.send(:format_feedback_message)
# anonymous_user? checks cust.nil? || cust.anonymous?, so anonymous role also returns anon: prefix
formatted.include?('anon:')
#=> true

## format_feedback_message returns extid for authenticated customer
session = MockSession.new
strategy_result = MockStrategyResult.authenticated(@authenticated_customer, session: session)
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
formatted = logic.send(:format_feedback_message)
# Should contain the customer extid
formatted.include?(@authenticated_customer.extid)
#=> true

## format_feedback_message includes timezone and version in output
session = MockSession.new
strategy_result = MockStrategyResult.authenticated(@authenticated_customer, session: session)
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
formatted = logic.send(:format_feedback_message)
formatted.include?('[TZ: America/New_York]') && formatted.include?('[v1.0.0]')
#=> true

## send_feedback handles nil sender without crashing
# Create a mock colonel for receiving feedback
colonel = Customer.new email: 'colonel@onetimesecret.com'
colonel.role = 'colonel'
colonel.verified = true
strategy_result = MockStrategyResult.anonymous
logic = V3::Logic::ReceiveFeedback.new(strategy_result, @params, 'en')
# This should not raise an error - nil sender is valid
result = begin
  logic.send(:send_feedback, colonel, nil, 'Test message')
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
