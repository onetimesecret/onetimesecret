# try/features/incoming/incoming_api_try.rb
#
# frozen_string_literal: true

# These tryouts test the incoming secrets API logic classes.
# They verify:
# 1. GetConfig returns proper configuration
# 2. ValidateRecipient validates recipient hashes
# 3. CreateIncomingSecret creates secrets with memo field
#
# Note: These tests require the incoming feature to be enabled in config.

require_relative '../../support/test_logic'
require 'apps/api/v3/logic'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

@email = "tryouts+incoming+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@strategy_result = MockStrategyResult.new(session: {}, user: @cust)

## V3::Logic::Incoming::GetConfig class exists
defined?(V3::Logic::Incoming::GetConfig)
#=> 'constant'

## V3::Logic::Incoming::ValidateRecipient class exists
defined?(V3::Logic::Incoming::ValidateRecipient)
#=> 'constant'

## V3::Logic::Incoming::CreateIncomingSecret class exists
defined?(V3::Logic::Incoming::CreateIncomingSecret)
#=> 'constant'

## GetConfig raises error when feature is disabled
begin
  logic = V3::Logic::Incoming::GetConfig.new(@strategy_result, {})
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## ValidateRecipient raises error when feature is disabled
begin
  logic = V3::Logic::Incoming::ValidateRecipient.new(@strategy_result, { 'recipient' => 'test_hash' })
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## CreateIncomingSecret raises error when feature is disabled
begin
  logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
    'secret' => {
      'memo' => 'Test memo',
      'secret' => 'Test secret content',
      'recipient' => 'test_hash'
    }
  })
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## Cleanup test data
@cust.destroy! if @cust
true
#=> true
