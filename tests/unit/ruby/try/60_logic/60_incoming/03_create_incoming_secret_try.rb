# tests/unit/ruby/try/60_logic/60_incoming/03_create_incoming_secret_try.rb

# These tests cover the Incoming::CreateIncomingSecret logic class which handles
# creation of incoming secrets with title and recipient metadata.
#
# We test:
# 1. Basic secret creation with all fields
# 2. Title truncation to max length
# 3. Passphrase application from config
# 4. Metadata storage (title, recipient)
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
    title: 'Test Secret',
    secret: 'secret value',
    recipient: 'test@example.com'
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
ENV['INCOMING_TITLE_MAX_LENGTH'] = '50'
ENV['INCOMING_DEFAULT_TTL'] = '3600'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'test-passphrase-123'
OT.boot! :test, false

## CreateIncomingSecret processes params correctly
params = {
  title: 'Important Issue',
  secret: 'This is a secret message',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
[
  logic.title,
  logic.secret_value,
  logic.recipient_email,
  logic.ttl,
  logic.passphrase
]
#=> ['Important Issue', 'This is a secret message', 'support@example.com', 3600, 'test-passphrase-123']

## CreateIncomingSecret truncates title to max length
long_title = 'A' * 100
params = {
  title: long_title,
  secret: 'test',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.title.length
#=> 50

## CreateIncomingSecret raises error for empty title
params = {
  title: '   ',
  secret: 'test',
  recipient: 'support@example.com'
}
begin
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message
end
#=> "Title is required"

## CreateIncomingSecret raises error for empty secret
params = {
  title: 'Test',
  secret: '',
  recipient: 'support@example.com'
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
  title: 'Test',
  secret: 'test value',
  recipient: ''
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
  title: 'Test',
  secret: 'test value',
  recipient: 'unknown@example.com'
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
  title: 'Bug Report #123',
  secret: 'Stack trace: Error on line 42',
  recipient: 'security@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
logic.process
logic.greenlighted
#=> true

## CreateIncomingSecret creates metadata and secret objects
params = {
  title: 'Feature Request',
  secret: 'Please add dark mode',
  recipient: 'support@example.com'
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
  title: 'Test Title',
  secret: 'Test Secret',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
[
  metadata.field_get(:incoming_title),
  metadata.field_get(:incoming_recipient)
]
#=> ['Test Title', 'support@example.com']

## CreateIncomingSecret applies passphrase from config
params = {
  title: 'Passphrase Test',
  secret: 'Secret content',
  recipient: 'support@example.com'
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
  title: 'No Passphrase',
  secret: 'Open secret',
  recipient: 'support@example.com'
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
  title: 'TTL Test',
  secret: 'Testing TTL',
  recipient: 'support@example.com'
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

## CreateIncomingSecret returns success data with correct structure
params = {
  title: 'Success Test',
  secret: 'Test content',
  recipient: 'security@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
data = logic.success_data
[
  data[:success],
  data[:record].key?(:metadata),
  data[:record].key?(:secret),
  data[:details][:title],
  data[:details][:recipient]
]
#=> [true, true, true, 'Success Test', 'security@example.com']

## CreateIncomingSecret updates customer stats for authenticated user
initial_count = @cust.secrets_created || 0
params = {
  title: 'Stats Test',
  secret: 'Testing stats',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
@cust.reload
@cust.secrets_created
#=> initial_count + 1

## CreateIncomingSecret handles whitespace in title
params = {
  title: '  Whitespace Test  ',
  secret: 'Testing whitespace',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.title
#=> 'Whitespace Test'

## CreateIncomingSecret handles special characters in title
params = {
  title: 'Bug: <script>alert("XSS")</script>',
  secret: 'Test content',
  recipient: 'support@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
metadata.field_get(:incoming_title)
#=> 'Bug: <script>alert("XSS")</script>'

## CreateIncomingSecret secret can be retrieved
params = {
  title: 'Retrieval Test',
  secret: 'This is the secret content',
  recipient: 'support@example.com'
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
ENV.delete('INCOMING_TITLE_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
