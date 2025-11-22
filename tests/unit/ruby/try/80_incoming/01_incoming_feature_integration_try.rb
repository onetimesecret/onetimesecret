# tests/unit/ruby/try/80_incoming/01_incoming_feature_integration_try.rb

# These tests provide end-to-end integration testing of the Incoming Secrets feature.
# They test the complete flow from configuration to secret creation and retrieval.
#
# We test:
# 1. Complete feature workflow (config -> validate -> create)
# 2. Multiple secrets creation in sequence
# 3. Different recipients handling
# 4. Feature toggle behavior
# 5. Edge cases and error scenarios
# 6. Metadata persistence across lifecycle
# 7. Secret retrieval and decryption

require_relative '../try/test_logic'

# Load the app with feature enabled
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_TITLE_MAX_LENGTH'] = '80'
ENV['INCOMING_DEFAULT_TTL'] = '86400'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'integration-test-pass'
OT.boot! :test, false

# Setup: Create session and customers for testing
@sess = Session.new '10.0.1.100', 'anon'
@anon = Customer.anonymous
@cust = Customer.new 'integration-test@example.com'
@cust.save

## Feature integration test setup succeeds
[
  @sess.class,
  @cust.class,
  @anon.class
]
#=> [V2::Session, V2::Customer, V2::Customer]

## Full workflow: Get config, validate recipient, create secret
config_logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
config_logic.process
config_data = config_logic.success_data[:config]

validate_logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'helpdesk@example.com' }
validate_logic.process
is_valid = validate_logic.success_data[:valid]

create_params = {
  title: 'Integration Test Secret',
  secret: 'This is a complete integration test',
  recipient: 'helpdesk@example.com'
}
create_logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
create_logic.process

[
  config_data[:enabled],
  is_valid,
  create_logic.greenlighted
]
#=> [true, true, true]

## Created secret can be loaded and has correct metadata
create_params = {
  title: 'Loadable Secret',
  secret: 'Secret content for loading',
  recipient: 'security@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
logic.process
metadata_key = logic.metadata.key
secret_key = logic.secret.key

loaded_metadata = V2::Metadata.load metadata_key
loaded_secret = V2::Secret.load secret_key

[
  loaded_metadata.field_get(:incoming_title),
  loaded_metadata.field_get(:incoming_recipient),
  loaded_secret.can_decrypt?
]
#=> ['Loadable Secret', 'security@example.com', true]

## Created secret can be decrypted with passphrase
create_params = {
  title: 'Encrypted Secret',
  secret: 'Super secret message',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
logic.process

secret = V2::Secret.load logic.secret.key
secret.decrypted_value
#=> 'Super secret message'

## Multiple secrets can be created in sequence
recipients = ['helpdesk@example.com', 'security@example.com', 'support@example.com']
created_keys = recipients.map.with_index do |recipient, i|
  params = {
    title: "Sequential Secret #{i + 1}",
    secret: "Content #{i + 1}",
    recipient: recipient
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.process
  logic.metadata.key
end
created_keys.length
#=> 3

## Each created secret is independent and has correct data
last_key = created_keys.last
metadata = V2::Metadata.load last_key
[
  metadata.field_get(:incoming_title),
  metadata.field_get(:incoming_recipient)
]
#=> ["Sequential Secret 3", 'support@example.com']

## Anonymous users can create incoming secrets
anon_sess = Session.new '192.168.1.50', 'anon'
create_params = {
  title: 'Anonymous Secret',
  secret: 'Secret from anonymous user',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new anon_sess, @anon, create_params
logic.process
logic.greenlighted
#=> true

# Test with feature disabled
ENV['INCOMING_ENABLED'] = 'false'
OT.boot! :test, false

## Feature disabled blocks get config
begin
  logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
  logic.raise_concerns
  false
rescue OT::FormError
  true
end
#=> true

## Feature disabled blocks recipient validation
begin
  logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'test@example.com' }
  logic.raise_concerns
  false
rescue OT::FormError
  true
end
#=> true

## Feature disabled blocks secret creation
begin
  params = {
    title: 'Should Fail',
    secret: 'This should not work',
    recipient: 'helpdesk@example.com'
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Incoming secrets feature is not enabled"

# Re-enable for edge cases
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_TITLE_MAX_LENGTH'] = '80'
ENV['INCOMING_DEFAULT_TTL'] = '86400'
OT.boot! :test, false

## Edge case: Maximum title length enforcement
max_length = OT.conf.dig(:features, :incoming, :title_max_length)
long_title = 'X' * (max_length + 50)
params = {
  title: long_title,
  secret: 'Content',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
metadata.field_get(:incoming_title).length
#=> max_length

# Test without passphrase
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
OT.boot! :test, false

## Edge case: No passphrase config
params = {
  title: 'No Passphrase Secret',
  secret: 'Unprotected content',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
secret.passphrase.nil?
#=> true

# Test with short TTL
ENV['INCOMING_DEFAULT_TTL'] = '60'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'integration-test-pass'
OT.boot! :test, false

## Edge case: Very short TTL
params = {
  title: 'Short TTL Secret',
  secret: 'Expires quickly',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
secret.ttl
#=> 60

# Test with long TTL
ENV['INCOMING_DEFAULT_TTL'] = '2592000'
OT.boot! :test, false

## Edge case: Very long TTL
params = {
  title: 'Long TTL Secret',
  secret: 'Lasts a month',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
secret.ttl
#=> 2592000

# Reload with standard config
ENV['INCOMING_DEFAULT_TTL'] = '86400'
OT.boot! :test, false

## Edge case: Unicode characters in title
params = {
  title: 'Bug Report: 日本語 🐛 Émojis',
  secret: 'Unicode test content',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
metadata.field_get(:incoming_title)
#=> 'Bug Report: 日本語 🐛 Émojis'

## Edge case: Large secret content
large_content = 'A' * 10000
params = {
  title: 'Large Content Secret',
  secret: large_content,
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
secret.decrypted_value.length
#=> 10000

## Form fields are populated on error
begin
  params = {
    title: 'Valid Title',
    secret: 'Valid Secret',
    recipient: 'invalid@example.com'
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
rescue OT::FormError => e
  fields = e.form_fields
  [
    fields[:title],
    fields[:secret],
    fields[:recipient]
  ]
end
#=> ['Valid Title', 'Valid Secret', 'invalid@example.com']

## Success data includes all expected fields
params = {
  title: 'Final Test',
  secret: 'Final secret content',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
data = logic.success_data
[
  data.key?(:success),
  data.key?(:record),
  data.key?(:details),
  data[:record].key?(:metadata),
  data[:record].key?(:secret),
  data[:details].key?(:title),
  data[:details].key?(:recipient)
]
#=> [true, true, true, true, true, true, true]

# Teardown: Clean up all test data
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_TITLE_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
