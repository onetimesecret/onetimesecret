# tests/unit/ruby/try/80_incoming/01_incoming_feature_integration_try.rb

require_relative '../test_logic'

# Setup
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_MEMO_MAX_LENGTH'] = '80'
ENV['INCOMING_DEFAULT_TTL'] = '86400'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'integration-test-pass'
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'
ENV['INCOMING_RECIPIENT_3'] = 'helpdesk@example.com,Help Desk'

OT.boot! :test, false

@cust = V2::Customer.create 'incoming-test@example.com'
@sess = Session.new '192.168.1.100', @cust.custid

# Get valid recipient hashes
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]
@security_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Security Team' }[:hash]
@helpdesk_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Help Desk' }[:hash]

## Get config returns enabled and max length
logic = V2::Logic::Incoming::GetConfig.new @sess, @cust, {}
logic.process
data = logic.success_data
[
  data[:config][:enabled],
  data[:config][:recipients].length > 0
]
#=> [true, true]

## Validate recipient accepts allowed hash
logic = V2::Logic::Incoming::ValidateRecipient.new @sess, @cust, { recipient: @support_hash }
logic.process
logic.success_data[:valid]
#=> true

## Create and load incoming secret
create_params = {
  secret: {
    memo: 'Loadable Secret',
    secret: 'Secret content',
    recipient: @security_hash
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
  loaded_metadata.recipients,  # Backend stores actual email
  loaded_secret.exists?
]
#=> ['Loadable Secret', 'se*****@e*****.com', true]

## Created secret decrypts correctly without passphrase_temp
create_params = {
  secret: {
    memo: 'Clear Secret',
    secret: 'Decryptable content',
    recipient: @helpdesk_hash
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
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_MEMO_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
ENV.delete('INCOMING_RECIPIENT_3')
