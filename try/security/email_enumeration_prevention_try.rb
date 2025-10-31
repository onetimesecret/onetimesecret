# frozen_string_literal: true

# Security Tests: Email Enumeration Prevention (CWE-204)
#
# These tests verify that the account creation endpoint does not leak information
# about whether an email address is already registered. This prevents attackers
# from harvesting registered email addresses for phishing or other attacks.
#
# Related Issue: #1831
# CWE Reference: https://cwe.mitre.org/data/definitions/204.html
# OWASP Guide: https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/03-Identity_Management_Testing/04-Testing_for_Account_Enumeration_and_Guessable_User_Account

require_relative '../support/test_logic'
require 'securerandom'
require 'benchmark'

# Load the app with test configuration
OT.boot! :test, false

## Setup: Create test customer for enumeration testing
@test_email = "enum-test-#{SecureRandom.hex(4)}@example.com"
@existing_verified_email = "verified-#{SecureRandom.hex(4)}@example.com"
@existing_unverified_email = "unverified-#{SecureRandom.hex(4)}@example.com"

# Create existing verified customer
@verified_customer = Onetime::Customer.create!(email: @existing_verified_email)
@verified_customer.update_passphrase('existing_password_123')
@verified_customer.verified = true
@verified_customer.save

# Create existing unverified customer
@unverified_customer = Onetime::Customer.create!(email: @existing_unverified_email)
@unverified_customer.update_passphrase('existing_password_456')
@unverified_customer.verified = false
@unverified_customer.save

@locale = :en

## Test 1: New email account creation returns generic success message
params = {
  login: @test_email,
  password: 'new_password_789',
  planid: 'basic'
}
strategy_result = Otto::Security::Authentication::StrategyResult.new(
  session: {},
  user: nil,
  auth_method: 'noauth',
  metadata: { ip: '127.0.0.1', user_agent: 'test' }
)
logic = V2::Logic::Account::CreateAccount.new(strategy_result, params, @locale)
logic.process_params
logic.raise_concerns
result = logic.process
success_message = logic.instance_variable_get(:@sess)['success_message']
#=> /If an account with this email exists, you will receive a verification email/

## Test 2: Existing verified email returns same generic message (no error)
params2 = {
  login: @existing_verified_email,
  password: 'different_password_abc',
  planid: 'basic'
}
strategy_result2 = Otto::Security::Authentication::StrategyResult.new(
  session: {},
  user: nil,
  auth_method: 'noauth',
  metadata: { ip: '127.0.0.1', user_agent: 'test' }
)
logic2 = V2::Logic::Account::CreateAccount.new(strategy_result2, params2, @locale)
logic2.process_params
logic2.raise_concerns
result2 = logic2.process
success_message2 = logic2.instance_variable_get(:@sess)['success_message']
#=> /If an account with this email exists, you will receive a verification email/

## Test 3: Existing unverified email returns same generic message
params3 = {
  login: @existing_unverified_email,
  password: 'another_password_xyz',
  planid: 'basic'
}
strategy_result3 = Otto::Security::Authentication::StrategyResult.new(
  session: {},
  user: nil,
  auth_method: 'noauth',
  metadata: { ip: '127.0.0.1', user_agent: 'test' }
)
logic3 = V2::Logic::Account::CreateAccount.new(strategy_result3, params3, @locale)
logic3.process_params
logic3.raise_concerns
result3 = logic3.process
success_message3 = logic3.instance_variable_get(:@sess)['success_message']
#=> /If an account with this email exists, you will receive a verification email/

## Test 4: Success messages are identical across all scenarios
success_message == success_message2
#=> true

## Test 5: Verify messages are identical (all three scenarios)
success_message == success_message3
#=> true

## Test 6: No errors are raised for existing accounts
# This test verifies that existing accounts don't raise FormError
# The logic should complete successfully without throwing errors
params4 = {
  login: @existing_verified_email,
  password: 'attempt_password',
  planid: 'basic'
}
strategy_result4 = Otto::Security::Authentication::StrategyResult.new(
  session: {},
  user: nil,
  auth_method: 'noauth',
  metadata: { ip: '127.0.0.1', user_agent: 'test' }
)
logic4 = V2::Logic::Account::CreateAccount.new(strategy_result4, params4, @locale)
begin
  logic4.process_params
  logic4.raise_concerns
  logic4.process
  :no_error
rescue OT::FormError => e
  :error_raised
end
#=> :no_error

## Test 7: Invalid email still shows validation error (not enumeration info)
params5 = {
  login: 'not-a-valid-email',
  password: 'password123',
  planid: 'basic'
}
strategy_result5 = Otto::Security::Authentication::StrategyResult.new(
  session: {},
  user: nil,
  auth_method: 'noauth',
  metadata: { ip: '127.0.0.1', user_agent: 'test' }
)
logic5 = V2::Logic::Account::CreateAccount.new(strategy_result5, params5, @locale)
logic5.process_params
begin
  logic5.raise_concerns
  :no_error
rescue OT::FormError => e
  e.message
end
#=> /valid email address/

## Test 8: Existing customer object is reused (not recreated)
# For existing accounts, we should reuse the customer object
initial_customer_count = Onetime::Customer.redis.keys('customer:*').size
params6 = {
  login: @existing_verified_email,
  password: 'another_attempt',
  planid: 'basic'
}
strategy_result6 = Otto::Security::Authentication::StrategyResult.new(
  session: {},
  user: nil,
  auth_method: 'noauth',
  metadata: { ip: '127.0.0.1', user_agent: 'test' }
)
logic6 = V2::Logic::Account::CreateAccount.new(strategy_result6, params6, @locale)
logic6.process_params
logic6.raise_concerns
logic6.process
final_customer_count = Onetime::Customer.redis.keys('customer:*').size
# Count should not increase (no new customer created)
final_customer_count == initial_customer_count
#=> true

## Test 9: Response timing consistency check
# Measure response times to ensure they're within acceptable variance
# This is a basic timing attack prevention check
require 'benchmark'

times = []

# Time 1: New account creation
time1 = Benchmark.realtime do
  params_t1 = {
    login: "timing-test-new-#{SecureRandom.hex(4)}@example.com",
    password: 'password123',
    planid: 'basic'
  }
  strategy_t1 = OpenStruct.new(
    authenticated?: false,
    session: { id: @session.identifier },
    metadata: { ip: '127.0.0.1' }
  )
  logic_t1 = V2::Logic::Account::CreateAccount.new(strategy_t1, params_t1, @locale)
  logic_t1.process_params
  logic_t1.raise_concerns
  logic_t1.process
end
times << time1

# Time 2: Existing verified account
time2 = Benchmark.realtime do
  params_t2 = {
    login: @existing_verified_email,
    password: 'password456',
    planid: 'basic'
  }
  strategy_t2 = OpenStruct.new(
    authenticated?: false,
    session: { id: @session.identifier },
    metadata: { ip: '127.0.0.1' }
  )
  logic_t2 = V2::Logic::Account::CreateAccount.new(strategy_t2, params_t2, @locale)
  logic_t2.process_params
  logic_t2.raise_concerns
  logic_t2.process
end
times << time2

# Time 3: Existing unverified account
time3 = Benchmark.realtime do
  params_t3 = {
    login: @existing_unverified_email,
    password: 'password789',
    planid: 'basic'
  }
  strategy_t3 = OpenStruct.new(
    authenticated?: false,
    session: { id: @session.identifier },
    metadata: { ip: '127.0.0.1' }
  )
  logic_t3 = V2::Logic::Account::CreateAccount.new(strategy_t3, params_t3, @locale)
  logic_t3.process_params
  logic_t3.raise_concerns
  logic_t3.process
end
times << time3

# Calculate variance - should be relatively small
max_time = times.max
min_time = times.min
variance = max_time - min_time

# Timing variance should be less than 100ms to prevent timing attacks
# This is a reasonable threshold for non-network operations
variance < 0.1
#=> true

## Teardown: Clean up test data
@verified_customer.destroy!
@unverified_customer.destroy!
# New customer created in Test 1
Onetime::Customer.load(@test_email)&.destroy!
# Timing test customer
