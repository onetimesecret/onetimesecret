# tests/unit/ruby/try/80_incoming/01_incoming_feature_integration_try.rb

# Integration tests for Incoming Secrets feature

require_relative '../test_logic'

# Load the app with feature enabled
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_MEMO_MAX_LENGTH'] = '80'
ENV['INCOMING_DEFAULT_TTL'] = '86400'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'integration-test-pass'

OT.boot! :test, false

# Setup test customer and session
@cust = V2::Customer.create 'incoming-test@example.com'
@sess = Session.new '192.168.1.100', @cust.custid

@anon = V2::Customer.anonymous
anon_sess = Session.new '192.168.1.50', 'anon'

## Get config returns feature configuration
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
[
  data[:config][:enabled],
  data[:config][:memo_max_length],
  data[:config][:recipients].length > 0
]
#=> [true, 80, true]

## Validate recipient accepts allowed email
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'support@example.com' }
logic.process
logic.success_data[:valid]
#=> true

## Validate recipient rejects invalid email
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'invalid@bad.com' }
logic.process
logic.success_data[:valid]
#=> false

## Create incoming secret stores memo and recipient
create_params = {
  memo: 'Test Secret',
  secret: 'Secret content here',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
logic.process
[
  logic.greenlighted,
  logic.metadata.memo,
  logic.metadata.recipients
]
#=> [true, 'Test Secret', 'helpdesk@example.com']

## Created secret can be loaded
metadata_key = logic.metadata.key
secret_key = logic.secret.key

loaded_metadata = V2::Metadata.load metadata_key
loaded_secret = V2::Secret.load secret_key

[
  loaded_metadata.memo,
  loaded_metadata.recipients,
  loaded_secret.exists?
]
#=> ['Test Secret', 'helpdesk@example.com', true]

## Created secret can be decrypted
create_params = {
  memo: 'Encrypted Secret',
  secret: 'Super secret message',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
logic.process

secret = V2::Secret.load logic.secret.key
secret.decrypted_value
#=> 'Super secret message'

## Multiple secrets can be created
recipients = ['helpdesk@example.com', 'security@example.com', 'support@example.com']
created_keys = recipients.map.with_index do |recipient, i|
  params = {
    memo: "Sequential Secret #{i + 1}",
    secret: "Content #{i + 1}",
    recipient: recipient
  }
  logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
  logic.process
  logic.metadata.key
end
created_keys.length
#=> 3

## Anonymous users can create incoming secrets
create_params = {
  memo: 'Anonymous Secret',
  secret: 'From anon',
  recipient: 'security@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new anon_sess, @anon, create_params
logic.process
logic.greenlighted
#=> true

## Edge case: Maximum memo length enforcement
max_length = OT.conf.dig(:features, :incoming, :memo_max_length)
long_memo = 'X' * (max_length + 50)
params = {
  memo: long_memo,
  secret: 'Content',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata = V2::Metadata.load logic.metadata.key
metadata.memo.length
#=> max_length

## Edge case: Unicode in memo
params = {
  memo: 'Bug Report 🐛',
  secret: 'Unicode test',
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
metadata.memo
#=> 'Bug Report 🐛'

## Edge case: Large secret content
large_content = 'A' * 10000
params = {
  memo: 'Large Content',
  secret: large_content,
  recipient: 'helpdesk@example.com'
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
secret = V2::Secret.load logic.secret.key
secret.decrypted_value == large_content
#=> true

# Teardown
@cust.destroy!
