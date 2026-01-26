# try/features/incoming/incoming_api_try.rb
#
# frozen_string_literal: true

# These tryouts test the incoming secrets API logic classes.
# They verify:
# 1. GetConfig returns proper configuration
# 2. ValidateRecipient validates recipient hashes
# 3. CreateIncomingSecret creates secrets with memo field
# 4. Happy-path tests with feature enabled
#
# Note: Tests are split into disabled (default) and enabled sections.
# The enabled tests configure the feature inline within each test.

require_relative '../../support/test_logic'
require 'apps/api/v3/logic'


OT.boot! :test, false

@email = "tryouts+incoming+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@strategy_result = MockStrategyResult.new(session: {}, user: @cust)

# Test recipient configuration for enabled tests
@test_recipient_email = "recipient+#{Familia.now.to_i}@onetimesecret.com"
@test_recipient_hash = 'test_recipient_hash_abc123'

# Store original config for restoration
@original_conf = YAML.load(YAML.dump(OT.conf))

# Helper to enable incoming feature for tests
# Creates an unfrozen copy of config with incoming enabled
def enable_incoming_feature(recipient_hash, recipient_email)
  # Create a deep copy of the current config (unfrozen)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features']['incoming']['enabled'] = true

  # Replace the config using the private setter
  OT.send(:conf=, new_conf)

  # Set up recipient lookup
  OT.instance_variable_set(:@incoming_recipient_lookup, {
    recipient_hash => recipient_email
  }.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [
    { hash: recipient_hash, name: 'Test Recipient' }
  ].freeze)
end

# Helper to disable incoming feature and restore original config
def disable_incoming_feature(original_conf)
  # Restore original config
  OT.send(:conf=, original_conf)
  OT.instance_variable_set(:@incoming_recipient_lookup, {}.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [].freeze)
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

## GetConfig returns config hash when feature is enabled
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result.key?(:config)
#=> true

## GetConfig result includes memo_max_length
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result[:config][:memo_max_length]
#=> 50

## GetConfig result includes public recipients
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result[:config][:recipients].first[:hash]
#=> 'test_recipient_hash_abc123'

## ValidateRecipient returns valid true for valid hash
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::ValidateRecipient.new(@strategy_result, { 'recipient' => @test_recipient_hash })
logic.process_params
logic.raise_concerns
result = logic.process
result[:valid]
#=> true

## ValidateRecipient returns recipient hash (not email)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::ValidateRecipient.new(@strategy_result, { 'recipient' => @test_recipient_hash })
logic.process_params
logic.raise_concerns
result = logic.process
result[:recipient]
#=> 'test_recipient_hash_abc123'

## ValidateRecipient returns valid false for invalid hash (no error raised)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::ValidateRecipient.new(@strategy_result, { 'recipient' => 'invalid_hash_xyz' })
logic.process_params
logic.raise_concerns
result = logic.process
result[:valid]
#=> false

## CreateIncomingSecret succeeds with valid data
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Test memo for secret',
    'secret' => 'This is the secret content',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:success]
#=> true

## CreateIncomingSecret returns receipt in response
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Another test memo',
    'secret' => 'More secret content',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:record].key?(:receipt) && result[:record][:receipt].key?(:identifier)
#=> true

## CreateIncomingSecret returns secret in response
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Memo for secret check',
    'secret' => 'Secret content here',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:record].key?(:secret) && result[:record][:secret].key?(:identifier)
#=> true

## CreateIncomingSecret includes memo in details
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Specific memo text',
    'secret' => 'Secret for memo test',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:details][:memo]
#=> 'Specific memo text'

## CreateIncomingSecret includes recipient hash in details (not email)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Memo for recipient check',
    'secret' => 'Secret for recipient test',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:details][:recipient]
#=> 'test_recipient_hash_abc123'

## CreateIncomingSecret works without memo (memo is optional)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'secret' => 'Secret without memo',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:success]
#=> true

## CreateIncomingSecret returns empty memo when not provided
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'secret' => 'Another secret without memo',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:details][:memo]
#=> ''

## CreateIncomingSecret fails with empty secret content
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
begin
  logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
    'secret' => {
      'memo' => 'Test memo',
      'secret' => '',
      'recipient' => @test_recipient_hash
    }
  })
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('Secret content is required')
end
#=> true

## CreateIncomingSecret fails with invalid recipient hash
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
begin
  logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
    'secret' => {
      'memo' => 'Test memo',
      'secret' => 'Valid secret content',
      'recipient' => 'nonexistent_hash'
    }
  })
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('Invalid recipient')
end
#=> true

## CreateIncomingSecret fails with missing recipient
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
begin
  logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
    'secret' => {
      'memo' => 'Test memo',
      'secret' => 'Valid secret content'
    }
  })
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('Recipient is required')
end
#=> true

## CreateIncomingSecret stores memo on receipt
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Stored memo test',
    'secret' => 'Secret for stored memo',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
logic.receipt.memo
#=> 'Stored memo test'

## CreateIncomingSecret stores recipients on receipt
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = V3::Logic::Incoming::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Recipients test',
    'secret' => 'Secret for recipients',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
logic.receipt.recipients == @test_recipient_email
#=> true

## Cleanup test data
disable_incoming_feature(@original_conf)
@cust.destroy! if @cust
true
#=> true
