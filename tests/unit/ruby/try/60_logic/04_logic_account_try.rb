# frozen_string_literal: true

# These tests cover the Account logic classes which handle
# account management functionality.
#
# We test:
# 1. Account creation
# 2. Account updates (password, locale)
# 3. API token generation
# 4. Account retrieval
# 5. Account deletion

require_relative '../test_helpers'
require 'securerandom'

# Load the app with test configuration
OT.boot! :test

# Setup common test variables
@now = DateTime.now
# Generate a unique email address using a UUID
@unique_email = lambda {"test_#{SecureRandom.uuid}@onetimesecret.com"}

# Assign the unique email address
@email = @unique_email.call
@sess = OT::Session.new '255.255.255.254', 'anon'


# Create a customer for update tests
@cust = OT::Customer.new @email
@cust.save


# CreateAccount Tests

## Test account creation
@create_params = {
  u: @unique_email.call,
  p: 'testpass123',
  p2: 'testpass123',
  planid: 'anonymous',
  skill: '' # honeypot field should be empty
}
logic = OT::Logic::Account::CreateAccount.new @sess, nil, @create_params
logic.raise_concerns
logic.process
[
  logic.cust.class,
  logic.plan.planid,
  logic.autoverify,
  logic.customer_role
]
#=> [OT::Customer, 'anonymous', false, 'customer']

# UpdatePassword Tests

## Test password update
@update_params = {
  current: 'testpass123',
  p1: 'newpass123',
  p2: 'newpass123'
}
logic = OT::Logic::Account::UpdatePassword.new @sess, @cust, @update_params
logic.instance_variables.include?(:@modified)
#=> true

# UpdateLocale Tests

## Test locale update
@locale_params = { locale: 'es', u: @email }
logic = OT::Logic::Account::UpdateLocale.new @sess, @cust, @locale_params
logic.instance_variables.include?(:@modified)
#=> true

# GenerateAPIToken Tests

## Test API token generation, but nothing happens without calling process
logic = OT::Logic::Account::GenerateAPIToken.new @sess, @cust
[logic.apitoken.nil?, logic.greenlighted]
#=> [true, nil]

## Test API token generation
logic = OT::Logic::Account::GenerateAPIToken.new @sess, @cust
#logic.raise_concerns
logic.process
[logic.apitoken.nil?, logic.greenlighted]
#=> [false, true]

# GetAccount Tests

## Test account retrieval
logic = OT::Logic::Account::GetAccount.new @sess, @cust, {}
[logic.plans_enabled, logic.stripe_customer, logic.stripe_subscription]
#=> [false, nil, nil]

# DestroyAccount Tests

## Test account deletion
logic = OT::Logic::Account::DestroyAccount.new @sess, @cust
[
  logic.raised_concerns_was_called,
  logic.greenlighted,
  logic.instance_variables.include?(:@cust)
]
#=> [nil, nil, true]

# Cleanup test data
@cust.delete!
