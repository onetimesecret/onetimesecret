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
OT.boot! :test, true

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
OT.boot! :test, true

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
OT.boot! :test, true

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
OT.boot! :test, true

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

# Re-enable feature for concurrent tests
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'test-passphrase-123'
OT.boot! :test, true
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]

## Duplicate payload creates distinct secrets (no deduplication)
params = {
  secret: {
    memo: 'Duplicate Test',
    secret: 'Same content twice',
    recipient: @support_hash
  }
}
logic1 = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic1.raise_concerns
logic1.process
logic2 = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic2.raise_concerns
logic2.process
[
  logic1.metadata.key != logic2.metadata.key,
  logic1.secret.key != logic2.secret.key,
  logic1.greenlighted,
  logic2.greenlighted
]
#=> [true, true, true, true]

## Rapid successive creations each produce valid objects with unique keys
keys = []
3.times do |i|
  p = {
    secret: {
      memo: "Rapid #{i}",
      secret: 'rapid content',
      recipient: @support_hash
    }
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, p
  logic.raise_concerns
  logic.process
  keys << logic.metadata.key
end
[keys.uniq.length, keys.length]
#=> [3, 3]

# Rate limiting tests
# Register events with string keys to match production behavior
# (config is loaded via IndifferentHash which stores keys as strings)
@orig_create_limit = RateLimit.event_limit(:create_secret)
@orig_email_limit = RateLimit.event_limit(:email_recipient)
RateLimit.register_event 'create_secret', 2
RateLimit.register_event 'email_recipient', 100

# Clear any accumulated counts from earlier tests
@eid = @sess.external_identifier
RateLimit.clear! @eid, :create_secret
RateLimit.clear! @eid, :email_recipient

## raise_concerns increments create_secret and email_recipient rate limit counters
params = {
  secret: {
    memo: 'Rate Limit Test',
    secret: 'test content',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
[@sess.event_get(:create_secret), @sess.event_get(:email_recipient)]
#=> [1, 1]

## Rate limit counters increment on subsequent calls to raise_concerns
params = {
  secret: {
    memo: 'Rate Limit Test 2',
    secret: 'more content',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
@sess.event_get(:create_secret)
#=> 2

## Exceeding create_secret rate limit raises LimitExceeded
begin
  params = {
    secret: {
      memo: 'Exceed Test',
      secret: 'content',
      recipient: @support_hash
    }
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::LimitExceeded
  true
end
#=> true

# Restore original limits and clean up rate limit data
RateLimit.register_event 'create_secret', @orig_create_limit
RateLimit.register_event 'email_recipient', @orig_email_limit
RateLimit.clear! @eid, :create_secret
RateLimit.clear! @eid, :email_recipient

# Teardown: Clean up test data
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_MEMO_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
