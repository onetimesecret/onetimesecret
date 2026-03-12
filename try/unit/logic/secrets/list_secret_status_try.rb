# try/unit/logic/secrets/list_secret_status_try.rb
#
# frozen_string_literal: true

# Tests for ListSecretStatus which returns status for multiple
# secrets by identifier. Covers the attr_reader fix and edge cases.

require_relative '../../../support/test_helpers'
require_relative '../../../support/test_logic'

OT.boot! :test, false

@email = generate_unique_test_email("list_secret_status")
@cust = Customer.create!(email: @email)
@strategy_result = MockStrategyResult.new(session: {}, user: @cust)

@secret1 = Secret.new
@secret1.generate_id
@secret1.custid = @cust.custid
@secret1.save

@secret2 = Secret.new
@secret2.generate_id
@secret2.custid = @cust.custid
@secret2.save

## secrets accessor is defined (regression: was missing attr_reader)
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => '' })
logic.respond_to?(:secrets)
#=> true

## Empty identifiers param yields empty array
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => '' })
logic.secrets
#=> []

## success_data returns correct count for valid identifiers
ids = [@secret1.identifier, @secret2.identifier].join(',')
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => ids })
result = logic.success_data
result[:count]
#=> 2

## success_data records length matches count
ids = [@secret1.identifier, @secret2.identifier].join(',')
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => ids })
result = logic.success_data
result[:records].length == result[:count]
#=> true

## Missing identifiers key yields empty result
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, {})
result = logic.success_data
[result[:records], result[:count]]
#=> [[], 0]

## Invalid identifiers are filtered out gracefully
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => 'bogus1,bogus2' })
result = logic.success_data
result[:count]
#=> 0

## Mixed valid and invalid identifiers returns only valid
ids = [@secret1.identifier, 'nonexistent', @secret2.identifier].join(',')
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => ids })
result = logic.success_data
result[:count]
#=> 2

## Single identifier works
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => @secret1.identifier })
result = logic.success_data
result[:count]
#=> 1

## Records contain Hash values from safe_dump
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => @secret1.identifier })
result = logic.success_data
result[:records].first.is_a?(Hash)
#=> true

## Special characters are stripped from identifiers
dirty = @secret1.identifier + '!@#$%'
logic = Logic::Secrets::ListSecretStatus.new(@strategy_result, { 'identifiers' => dirty })
logic.identifiers.first
#=> @secret1.identifier

@secret1.delete!
@secret2.delete!
@cust.delete!
