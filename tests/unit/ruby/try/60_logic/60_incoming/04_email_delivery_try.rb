# tests/unit/ruby/try/60_logic/60_incoming/04_email_delivery_try.rb

# These tests verify the email delivery path in CreateIncomingSecret:
# 1. IncomingSecretNotification has the expected interface
# 2. send_recipient_notification is defined and private
# 3. The rescue block in send_recipient_notification works
# 4. The correct template class is used (not SecretLink)

require_relative '../../test_logic'

# Boot with feature enabled and recipients configured
ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_DEFAULT_TTL'] = '3600'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'test-passphrase-email'
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'
OT.boot! :test, true

@sess = Session.new '127.0.0.1', 'anon'
@cust = Customer.new 'email-delivery-test@example.com'
@cust.save
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]

## IncomingSecretNotification inherits from Mail::Views::Base with expected interface
[
  OT::Mail::IncomingSecretNotification.ancestors.include?(OT::Mail::Views::Base),
  OT::Mail::IncomingSecretNotification.instance_method(:subject).arity,
  OT::Mail::IncomingSecretNotification.instance_method(:uri_path).arity,
  OT::Mail::IncomingSecretNotification.instance_method(:display_domain).arity,
  OT::Mail::IncomingSecretNotification.instance_method(:init).arity
]
#=> [true, 0, 0, 0, 2]

## send_recipient_notification is defined as private on CreateIncomingSecret
V2::Logic::Incoming::CreateIncomingSecret.private_instance_methods.include?(:send_recipient_notification)
#=> true

## IncomingSecretNotification is distinct from SecretLink template
klass = OT::Mail::IncomingSecretNotification
[klass.name, klass != OT::Mail::SecretLink]
#=> ['Onetime::Mail::IncomingSecretNotification', true]

## process completes and greenlights despite email delivery failure (rescue block works)
# In test mode without SMTP, deliver_by_email raises, but the rescue
# in send_recipient_notification catches it so process still succeeds
params = {
  secret: {
    memo: 'Email Rescue Test',
    secret: 'Testing rescue block catches email errors',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.raise_concerns
logic.process
[logic.greenlighted, logic.metadata.valid?, logic.secret.valid?]
#=> [true, true, true]

## metadata.recipients is set before email delivery attempt
params = {
  secret: {
    memo: 'Recipients Set Test',
    secret: 'Verify recipients stored',
    recipient: @support_hash
  }
}
logic = V2::Logic::Incoming::CreateIncomingSecret.new @sess, @cust, params
logic.process
loaded = V2::Metadata.load logic.metadata.key
loaded.recipients.empty?
#=> false

# Teardown
@cust.destroy!
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
