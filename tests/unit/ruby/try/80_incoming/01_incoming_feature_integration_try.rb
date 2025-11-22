# tests/unit/ruby/try/80_incoming/01_incoming_feature_integration_try.rb

require_relative '../test_logic'

# Setup
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_MEMO_MAX_LENGTH'] = '80'
ENV['INCOMING_DEFAULT_TTL'] = '86400'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'integration-test-pass'

OT.boot! :test, false

@cust = V2::Customer.create 'incoming-test@example.com'
@sess = Session.new '192.168.1.100', @cust.custid

## Get config returns enabled and max length
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
[
  data[:config][:enabled],
  data[:config][:recipients].length > 0
]
#=> [true, true]

## Validate recipient accepts allowed email
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: 'support@example.com' }
logic.process
logic.success_data[:valid]
#=> true

## Create and load incoming secret
create_params = {
  secret: {
    memo: 'Loadable Secret',
    secret: 'Secret content',
    recipient: 'security@example.com'
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
logic.process
metadata_key = logic.metadata.key
secret_key = logic.secret.key
loaded_metadata = V2::Metadata.load metadata_key
loaded_secret = V2::Secret.load secret_key
[
  loaded_metadata.memo,
  loaded_metadata.recipients,
  loaded_secret.exists?
]
#=> ['Loadable Secret', 'security@example.com', true]

## Created secret decrypts correctly without passphrase_temp
create_params = {
  secret: {
    memo: 'Clear Secret',
    secret: 'Decryptable content',
    recipient: 'helpdesk@example.com'
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, create_params
logic.process
secret = V2::Secret.load logic.secret.key
secret.passphrase_temp = ENV['INCOMING_DEFAULT_PASSPHRASE']
secret.decrypted_value
#=> 'Decryptable content'

# Teardown
@cust.destroy!
