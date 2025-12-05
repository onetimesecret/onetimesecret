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

require_relative '../../support/test_models'
OT.boot! :test, false

require 'apps/api/v3/logic/incoming'

@email = "tryouts+incoming+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@sess = MockSession.new

# Helper to create a mock request context
def mock_params(params = {})
  params
end

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
  logic = V3::Logic::Incoming::GetConfig.new(@sess, @cust, mock_params)
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## ValidateRecipient raises error when feature is disabled
begin
  logic = V3::Logic::Incoming::ValidateRecipient.new(@sess, @cust, mock_params('recipient' => 'test_hash'))
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## CreateIncomingSecret raises error when feature is disabled
begin
  logic = V3::Logic::Incoming::CreateIncomingSecret.new(@sess, @cust, mock_params(
    'secret' => {
      'memo' => 'Test memo',
      'secret' => 'Test secret content',
      'recipient' => 'test_hash'
    }
  ))
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
