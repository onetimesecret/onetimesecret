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
require 'apps/api/incoming/logic/incoming'


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

# Helper to create a V3 strategy result with domain metadata
# Used by V3 incoming secrets tests for domain_id feature (#2864)
def create_v3_strategy_with_domain(customer, domain_fqdn, domain_strategy: :custom)
  session = MockSession.new
  org = customer.organization_instances.to_a.first
  org_context = {
    organization: org,
    organization_id: org.objid,
    expires_at: Familia.now.to_i + 300,
  }
  MockStrategyResult.new(
    session: session,
    user: customer,
    auth_method: 'session',
    metadata: {
      organization_context: org_context,
      domain_strategy: domain_strategy,
      display_domain: domain_fqdn,
    }
  )
end

# Incoming secrets setup for domain_id tests (#2864)

@v3_ts = Familia.now.to_i
@v3_entropy = SecureRandom.hex(4)
@v3_email = "tryouts+v3+#{@v3_ts}+#{@v3_entropy}@onetimesecret.com"
@v3_cust = Onetime::Customer.create!(email: @v3_email)
@v3_org = Onetime::Organization.create!("V3 Test Org #{@v3_ts}", @v3_cust, @v3_email)
@v3_custom_fqdn = "incoming-v3-#{@v3_ts}-#{@v3_entropy}.example.com"
@v3_custom_domain = Onetime::CustomDomain.create!(@v3_custom_fqdn, @v3_org.objid)
@v3_recipient_email = "v3recipient+#{@v3_ts}@onetimesecret.com"
@v3_recipient_hash = 'v3_recipient_hash_domain_test'

# Configure incoming secrets on the custom domain for V3 tests
# The recipient hash needs to match what the config will produce
@v3_incoming_config = Onetime::CustomDomain::IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => @v3_recipient_email, 'name' => 'V3 Test Recipient' }
  ],
  'memo_max_length' => 100,
  'default_ttl' => 604800
})
@v3_custom_domain.update_incoming_secrets_config(@v3_incoming_config)

# Get the actual hashed recipient from the config (for use in tests)
# Note: public_incoming_recipients returns hashes with string keys
site_secret = OT.conf.dig('site', 'secret')
@v3_recipient_hash = @v3_custom_domain.incoming_secrets_config.public_incoming_recipients(site_secret).first['digest']

## Incoming::Logic::GetConfig class exists
defined?(Incoming::Logic::GetConfig)
#=> 'constant'

## Incoming::Logic::ValidateRecipient class exists
defined?(Incoming::Logic::ValidateRecipient)
#=> 'constant'

## Incoming::Logic::CreateIncomingSecret class exists
defined?(Incoming::Logic::CreateIncomingSecret)
#=> 'constant'

## GetConfig returns config with enabled:false when feature is disabled (no error raised)
logic = Incoming::Logic::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result[:config][:enabled]
#=> false

## ValidateRecipient raises error when feature is disabled
begin
  logic = Incoming::Logic::ValidateRecipient.new(@strategy_result, { 'recipient' => 'test_hash' })
  logic.process_params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## CreateIncomingSecret raises error when feature is disabled
begin
  logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result.key?(:config)
#=> true

## GetConfig result includes memo_max_length
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result[:config][:memo_max_length]
#=> 50

## GetConfig result includes public recipients
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::GetConfig.new(@strategy_result, {})
logic.process_params
logic.raise_concerns
result = logic.process
result[:config][:recipients].first[:hash]
#=> 'test_recipient_hash_abc123'

## ValidateRecipient returns valid true for valid hash
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::ValidateRecipient.new(@strategy_result, { 'recipient' => @test_recipient_hash })
logic.process_params
logic.raise_concerns
result = logic.process
result[:valid]
#=> true

## ValidateRecipient returns recipient hash (not email)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::ValidateRecipient.new(@strategy_result, { 'recipient' => @test_recipient_hash })
logic.process_params
logic.raise_concerns
result = logic.process
result[:recipient]
#=> 'test_recipient_hash_abc123'

## ValidateRecipient returns valid false for invalid hash (no error raised)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::ValidateRecipient.new(@strategy_result, { 'recipient' => 'invalid_hash_xyz' })
logic.process_params
logic.raise_concerns
result = logic.process
result[:valid]
#=> false

## CreateIncomingSecret succeeds with valid data
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
  logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
  logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
  logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
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

## CreateIncomingSecret greenlighted is true after successful process
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Greenlighted check',
    'secret' => 'Valid secret for greenlighted test',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
logic.greenlighted
#=> true

## CreateIncomingSecret raises FormError when spawn_pair produces invalid objects
# Verify the greenlighted guard fires before stats/notification by simulating
# a failed spawn via temporary monkey-patching.
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
@_spawn_pair_original = Onetime::Receipt.method(:spawn_pair)
begin
  # Replace spawn_pair with one that returns unsaved (invalid) objects
  Onetime::Receipt.define_singleton_method(:spawn_pair) do |*_args, **_kwargs|
    [Onetime::Receipt.new, Onetime::Secret.new]
  end
  logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
    'secret' => {
      'memo' => 'Guard test',
      'secret' => 'Secret for guard test',
      'recipient' => @test_recipient_hash
    }
  })
  logic.process_params
  logic.raise_concerns
  logic.process
  false # should not reach here
rescue OT::FormError => e
  e.message.include?('Failed to create secret')
ensure
  # Restore original spawn_pair
  spawn_pair_backup = @_spawn_pair_original
  Onetime::Receipt.define_singleton_method(:spawn_pair) do |*args, **kwargs|
    spawn_pair_backup.call(*args, **kwargs)
  end
end
#=> true

## anonymous_user? returns true for anonymous strategy in CreateIncomingSecret
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
anon_strategy = MockStrategyResult.anonymous
logic = Incoming::Logic::CreateIncomingSecret.new(anon_strategy, {
  'secret' => {
    'memo' => 'Anon test',
    'secret' => 'Anonymous secret',
    'recipient' => @test_recipient_hash
  }
})
logic.anonymous_user?
#=> true

## anonymous_user? returns false for authenticated strategy in CreateIncomingSecret
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
logic = Incoming::Logic::CreateIncomingSecret.new(@strategy_result, {
  'secret' => {
    'memo' => 'Auth test',
    'secret' => 'Authenticated secret',
    'recipient' => @test_recipient_hash
  }
})
logic.anonymous_user?
#=> false

## CreateIncomingSecret succeeds for anonymous user
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
anon_strategy = MockStrategyResult.anonymous
logic = Incoming::Logic::CreateIncomingSecret.new(anon_strategy, {
  'secret' => {
    'memo' => 'Anonymous memo',
    'secret' => 'Anonymous secret content',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:success]
#=> true

## CreateIncomingSecret skips customer stats update for anonymous user
# When anonymous, customer stats (add_receipt, secrets_created) should not be updated
# This test verifies the code path doesn't error (can't easily verify stats weren't updated
# without the customer object, but we can verify the process completes successfully)
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
anon_strategy = MockStrategyResult.anonymous
logic = Incoming::Logic::CreateIncomingSecret.new(anon_strategy, {
  'secret' => {
    'memo' => 'Stats skip test',
    'secret' => 'Secret for stats test',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
# Process completes without error and greenlighted is true
[result[:success], logic.greenlighted]
#=> [true, true]

## CreateIncomingSecret adds receipt to customer for authenticated user
# Note: increment_field uses hash field increment, while secrets_created is a Familia counter
# Testing the receipt association instead as it's more reliable
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
auth_session = MockSession.new
auth_strategy = MockStrategyResult.authenticated(@cust, session: auth_session)
# Count initial receipts
initial_receipt_count = @cust.receipts.to_a.size
logic = Incoming::Logic::CreateIncomingSecret.new(auth_strategy, {
  'secret' => {
    'memo' => 'Auth stats test',
    'secret' => 'Secret for auth stats',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
# Reload customer and check receipts
reloaded_cust = Onetime::Customer.load(@cust.custid)
# Receipt should be added for authenticated user
reloaded_cust.receipts.to_a.size > initial_receipt_count
#=> true

## Cleanup test data
disable_incoming_feature(@original_conf)
@cust.destroy! if @cust
true
#=> true

# =============================================================================
# Incoming::Logic::CreateIncomingSecret - domain_id tests (#2864)
# =============================================================================
#
# These tests verify the Incoming API secrets logic correctly sets domain_id
# on receipts when created via a custom domain.
# Setup is done in global setup section above (before first ## marker).

## V3 CreateIncomingSecret with custom domain sets receipt.domain_id to resolved domain objid
# Custom domain uses its own incoming_secrets_config, not global config
v3_strategy = create_v3_strategy_with_domain(@v3_cust, @v3_custom_fqdn)
logic = Incoming::Logic::CreateIncomingSecret.new(v3_strategy, {
  'secret' => {
    'memo' => 'V3 custom domain test',
    'secret' => 'Secret for domain_id test',
    'recipient' => @v3_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
# Receipt should have domain_id set to the custom domain's identifier
logic.receipt.domain_id
#=> @v3_custom_domain.identifier

## V3 CreateIncomingSecret with canonical domain leaves receipt.domain_id as nil
# Canonical domain uses global config - use the same recipient as global tests
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
canonical_strategy = create_v3_strategy_with_domain(@v3_cust, '', domain_strategy: :canonical)
logic = Incoming::Logic::CreateIncomingSecret.new(canonical_strategy, {
  'secret' => {
    'memo' => 'V3 canonical domain test',
    'secret' => 'Secret for canonical domain',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
# Receipt should NOT have domain_id set when using canonical domain
logic.receipt.domain_id
#=> nil

## V3 CreateIncomingSecret with unknown custom domain raises Forbidden error
# Unknown custom domain should fail entitlement check before receipt creation
unknown_domain_strategy = create_v3_strategy_with_domain(@v3_cust, 'unknown-domain.example.com', domain_strategy: :custom)
logic = Incoming::Logic::CreateIncomingSecret.new(unknown_domain_strategy, {
  'secret' => {
    'memo' => 'V3 unknown domain test',
    'secret' => 'Secret for unknown domain',
    'recipient' => 'any_hash'
  }
})
logic.process_params
begin
  logic.raise_concerns
  false # Should not reach here
rescue OT::Forbidden => e
  e.message.include?('organization could not be resolved')
end
#=> true

## V3 CreateIncomingSecret with nil display_domain leaves receipt.domain_id as nil
# nil display_domain treated as canonical, uses global config
enable_incoming_feature(@test_recipient_hash, @test_recipient_email)
nil_domain_strategy = create_v3_strategy_with_domain(@v3_cust, nil, domain_strategy: :canonical)
logic = Incoming::Logic::CreateIncomingSecret.new(nil_domain_strategy, {
  'secret' => {
    'memo' => 'V3 nil domain test',
    'secret' => 'Secret for nil domain',
    'recipient' => @test_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
logic.process
# Receipt should NOT have domain_id set when display_domain is nil
logic.receipt.domain_id
#=> nil

## Cleanup V3 test data
disable_incoming_feature(@original_conf)
@v3_custom_domain.destroy! if @v3_custom_domain
@v3_org.destroy! if @v3_org
@v3_cust.destroy! if @v3_cust
true
#=> true
