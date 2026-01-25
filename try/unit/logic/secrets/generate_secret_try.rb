# try/unit/logic/secrets/generate_secret_try.rb
#
# frozen_string_literal: true

# These tests cover the Secrets logic classes which handle
# the core secret management functionality of the application.
#
# We test:
# 1. Secret creation (ConcealSecret)
# 2. Secret viewing (ShowSecret, RevealSecret)
# 3. Secret receipts (ShowReceipt, ListReceipts)
# 4. Secret deletion (BurnSecret)

require_relative '../../../support/test_helpers'
require_relative '../../../support/test_logic'

# Load the app with test configuration
OT.boot! :test, false

# Setup common test variables
@now = Familia.now
@email = generate_unique_test_email("generate_secret")
@session = {}
@strategy_result = MockStrategyResult.new(session: @session, user: nil)
@cust = Customer.create!(email: @email)
@secret = Secret.new
@secret.generate_id
@receipt = Receipt.new
@receipt.generate_id

# ConcealSecret Tests

## New secrets now get a key automatically when created
secret = Secret.new
[secret.identifier.class, secret.identifier.length > 16]
#=> [String, true]

## Calling generate_id on secrets ensures they have a key
secret = Secret.new
secret.generate_id
[secret.identifier.is_a?(String), secret.identifier.length > 16]
#=> [true, true]

## basic secret creation
@secret_payload = {
  'secret' => 'test secret value',
  'passphrase' => 'testpass123',
  'ttl' => '7200',
  'recipient' => ['recipient@example.com'],
}
@strategy_result_with_cust = MockStrategyResult.new(session: @session, user: @cust)
logic = Logic::Secrets::ConcealSecret.new @strategy_result_with_cust, {'secret' => @secret_payload}
[
  logic.secret_value,
  logic.passphrase,
  logic.ttl,
  logic.recipient,
  logic.recipient_safe,
]
#=> ['test secret value', 'testpass123', 7200, ['recipient@example.com'], ["re*****@e*****.com"]]

# ShowSecret Tests

## Create a secret for viewing tests
@secret.value = 'test secret'
@secret.passphrase = 'testpass123'
@secret.save

# Test secret viewing
@view_params = {
  'identifier' => @secret.identifier,
  'passphrase' => 'testpass123',
}
logic = Logic::Secrets::ShowSecret.new @strategy_result_with_cust, @view_params
[logic.identifier, logic.passphrase]
#=> [@secret.identifier, 'testpass123']

# RevealSecret Tests

## secret revealing (v2 API)
logic = V2::Logic::Secrets::RevealSecret.new @strategy_result_with_cust, @view_params
[logic.identifier, logic.passphrase]
#=> [@secret.identifier, 'testpass123']

# ShowReceipt Tests

## receipt viewing
logic = Logic::Secrets::ShowReceipt.new @strategy_result_with_cust, { 'identifier' => @receipt.identifier }
[logic.instance_variables.include?(:@identifier), logic.instance_variables.include?(:@receipt_identifier), logic.instance_variables.include?(:@secret_identifier), logic.secret_identifier, logic.identifier]
#=> [true, false, false, nil, @receipt.identifier]

# ListReceipts Tests

## process_params is automatically run when params are passed (even empty hash)
logic = Logic::Secrets::ListReceipts.new @strategy_result_with_cust, {}
[logic.since.class, logic.now.class]
#=> [Integer, Float]

## receipt list viewing
logic = Logic::Secrets::ListReceipts.new @strategy_result_with_cust, {}
[logic.records.class, logic.since.class, logic.now.class]
#=> [NilClass, Integer, Float]

# BurnSecret Tests

## secret burning
logic = Logic::Secrets::BurnSecret.new @strategy_result_with_cust, @view_params
[logic.identifier, logic.passphrase]
#=> [@secret.identifier, 'testpass123']

# Cleanup test data
@cust.delete!
@secret.delete!
@receipt.delete!
