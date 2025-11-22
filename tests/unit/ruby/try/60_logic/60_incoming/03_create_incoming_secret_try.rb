# tests/unit/ruby/try/60_logic/60_incoming/03_create_incoming_secret_try.rb

# These tests cover the Incoming::CreateIncomingSecret logic class which handles
# creation of incoming secrets with memo and recipient metadata.
#
# We test:
# 1. Basic secret creation with all fields
# 2. Title truncation to max length
# 3. Passphrase application from config
# 4. Metadata storage (memo, recipient)
# 5. Invalid recipient rejection
# 6. Missing required fields
# 7. Feature disabled state
# 8. TTL configuration
# 9. Customer stats updates

require_relative '../../test_logic'

# Load with feature disabled
ENV['INCOMING_ENABLED'] = 'false'
OT.boot! :test, false

# Setup: Create session and customer
@sess = Session.new '127.0.0.1', 'anon'
@cust = Customer.new 'incoming-creator@example.com'
@cust.save

## CreateIncomingSecret raises error when feature is disabled
begin
  params = {
    secret: {
      memo: 'Test Secret',
      secret: 'secret value',
      recipient: 'test@example.com'
    }
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Incoming secrets feature is not enabled"

# Enable feature for subsequent tests
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_MEMO_MAX_LENGTH'] = '50'
ENV['INCOMING_DEFAULT_TTL'] = '3600'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'test-passphrase-123'
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'
OT.boot! :test, false

# Get valid recipient hashes for testing
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]
@security_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Security Team' }[:hash]

## CreateIncomingSecret processes params correctly
params = {
  secret: {
    memo: 'Important Issue',
    secret: 'This is a secret message',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
[
  logic.memo,
  logic.secret_value,
  logic.recipient_email,
  logic.ttl,
  logic.passphrase
]
#=> ['Important Issue', 'This is a secret message', 'support@example.com', 3600, 'test-passphrase-123']

## CreateIncomingSecret truncates memo to max length
long_memo = 'A' * 100
params = {
  secret: {
    memo: long_memo,
    secret: 'test',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.memo.length
#=> 50

## CreateIncomingSecret accepts empty memo (memo is optional)
params = {
  secret: {
    memo: '   ',
    secret: 'test',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
logic.memo.empty?
#=> true

## CreateIncomingSecret raises error for empty secret
params = {
  secret: {
    memo: 'Test',
    secret: '',
    recipient: @support_hash
  }
}
begin
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Secret content is required"

## CreateIncomingSecret raises error for empty recipient
params = {
  secret: {
    memo: 'Test',
    secret: 'test value',
    recipient: ''
  }
}
begin
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Recipient is required"

## CreateIncomingSecret raises error for invalid recipient
params = {
  secret: {
    memo: 'Test',
    secret: 'test value',
    recipient: 'unknown@example.com'
  }
}
begin
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('Invalid recipient')
end
#=> true

## CreateIncomingSecret creates secret successfully
params = {
  secret: {
    memo: 'Bug Report #123',
    secret: 'Stack trace: Error on line 42',
    recipient: @security_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
logic.process
logic.greenlighted
#=> true

## CreateIncomingSecret creates metadata and secret objects
params = {
  secret: {
    memo: 'Feature Request',
    secret: 'Please add dark mode',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
[
  logic.metadata.class,
  logic.secret.class,
  logic.metadata.key.is_a?(String),
  logic.secret.key.is_a?(String)
]
#=> [V2::Metadata, V2::Secret, true, true]

## CreateIncomingSecret stores incoming metadata fields
params = {
  secret: {
    memo: 'Test Title',
    secret: 'Test Secret',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
[
  metadata.memo,
  metadata.recipients
]
#=> ['Test Title', 'support@example.com']

## CreateIncomingSecret applies passphrase from config
params = {
  secret: {
    memo: 'Passphrase Test',
    secret: 'Secret content',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
[
  secret.passphrase.nil?,
  logic.metadata.passphrase.nil?
]
#=> [false, false]

# Test without passphrase
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
OT.boot! :test, false

## CreateIncomingSecret works without passphrase config
params = {
  secret: {
    memo: 'No Passphrase',
    secret: 'Open secret',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
secret.passphrase.nil?
#=> true

# Test different TTL
ENV['INCOMING_DEFAULT_TTL'] = '7200'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'test-passphrase-123'
OT.boot! :test, false

## CreateIncomingSecret sets correct TTL
params = {
  secret: {
    memo: 'TTL Test',
    secret: 'Testing TTL',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
secret = V2::Secret.load logic.secret.key
[
  secret.ttl,
  metadata.ttl > secret.ttl
]
#=> [7200, true]

## CreateIncomingSecret returns success data with correct structure (returns hash not email)
params = {
  secret: {
    memo: 'Success Test',
    secret: 'Test content',
    recipient: @security_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
data = logic.success_data
[
  data[:success],
  data[:record].key?(:metadata),
  data[:record].key?(:secret),
  data[:details][:memo],
  data[:details][:recipient]
]
#=> [true, true, true, 'Success Test', @security_hash]

## CreateIncomingSecret updates customer stats for authenticated user
initial_count = @cust.secrets_created || 0
params = {
  secret: {
    memo: 'Stats Test',
    secret: 'Testing stats',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
@cust.reload
@cust.secrets_created
#=> initial_count + 1

## CreateIncomingSecret handles whitespace in memo
params = {
  secret: {
    memo: '  Whitespace Test  ',
    secret: 'Testing whitespace',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.memo
#=> 'Whitespace Test'

## CreateIncomingSecret handles special characters in memo
params = {
  secret: {
    memo: 'Bug: <script>alert("XSS")</script>',
    secret: 'Test content',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
metadata.memo
#=> 'Bug: <script>alert("XSS")</script>'

## CreateIncomingSecret secret can be retrieved
params = {
  secret: {
    memo: 'Retrieval Test',
    secret: 'This is the secret content',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
decrypted = secret.can_decrypt? ? secret.decrypted_value : nil
decrypted
#=> 'This is the secret content'

# Teardown: Clean up test data
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_MEMO_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
