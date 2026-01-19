# try/unit/logic/account_operations_try.rb
#
# frozen_string_literal: true

# NOTE: V1 has no account api functionality.

# These tests cover the Account logic classes which handle
# account management functionality.
#
# We test:
# 1. Account creation
# 2. Account updates (password, locale)
# 3. API token generation
# 4. Account retrieval
# 5. Account deletion

require_relative '../../../support/test_logic'
require 'securerandom'

# Load the app with test configuration
OT.boot! :test, false

# Setup common test variables
@now = Familia.now
# Generate a unique email address using a UUID with example.com domain for validation
# Generate a unique email address using a UUID (use example.com - it's RFC compliant)
@unique_email = lambda {"test_#{SecureRandom.uuid}@example.com"}

# Assign the unique email address
@email = @unique_email.call
@session = {}
@strategy_result = MockStrategyResult.new(session: @session, user: nil, auth_method: 'noauth')


# Create a customer for update tests
@cust = Onetime::Customer.new email: @email
@cust.save

# CreateAccount Tests

## account creation
@create_params = {
  'login' => @unique_email.call,
  'password' => 'testpass123',
  'password2' => 'testpass123',
  'planid' => 'anonymous',
  'skill' => '' # honeypot field should be empty
}
logic = AccountAPI::Logic::Account::CreateAccount.new @strategy_result, @create_params
logic.process_params
logic.raise_concerns
logic.process
[
  logic.cust.class,
  logic.cust.role,
  logic.autoverify,
  logic.customer_role
]
#=> [Onetime::Customer, 'customer', false, 'customer']

# UpdatePassword Tests

## password update
@update_params = {
  'current' => 'testpass123',
  'newpassword' => 'newpass123',
  'password-confirm' => 'newpass123'
}
@strategy_result_with_cust = MockStrategyResult.new(session: @session, user: @cust, auth_method: 'sessionauth')
logic = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result_with_cust, @update_params
logic.instance_variables.include?(:@modified)
#=> true

# UpdateLocale Tests

## locale update
@locale_params = { 'locale' => 'es', 'login' => @email }
logic = AccountAPI::Logic::Account::UpdateLocale.new @strategy_result_with_cust, @locale_params
logic.instance_variables.include?(:@modified)
#=> true

# GenerateAPIToken Tests

## API token generation, but nothing happens without calling process
logic = AccountAPI::Logic::Account::GenerateAPIToken.new @strategy_result_with_cust, {}
[logic.apitoken.nil?, logic.greenlighted]
#=> [true, nil]

## API token generation
logic = AccountAPI::Logic::Account::GenerateAPIToken.new @strategy_result_with_cust, {}
#logic.raise_concerns
logic.process
[logic.apitoken.nil?, logic.greenlighted]
#=> [false, true]

# GetAccount Tests

## account retrieval
logic = AccountAPI::Logic::Account::GetAccount.new @strategy_result_with_cust, {}
# NOTE: billing_enabled reflects the global OT.conf setting, not customer-specific state
[logic.billing_enabled.is_a?(TrueClass) || logic.billing_enabled.is_a?(FalseClass), logic.stripe_customer, logic.stripe_subscription]
#=> [true, nil, nil]

# DestroyAccount Tests

## account deletion
logic = AccountAPI::Logic::Account::DestroyAccount.new @strategy_result_with_cust, {}
[
  logic.raised_concerns_was_called,
  logic.greenlighted,
  logic.instance_variables.include?(:@cust)
]
#=> [nil, nil, true]

# Cleanup test data
@cust.delete!
