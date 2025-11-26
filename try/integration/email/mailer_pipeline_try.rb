# try/integration/email/mailer_pipeline_try.rb
#
# frozen_string_literal: true

# Tests the complete email delivery pipeline from Mailer entry points
# through template rendering to backend delivery.
#
# Uses Logger backend for safe testing without external calls.
# EMAILER_MODE=logger forces Logger backend regardless of other config.

require_relative '../../support/test_helpers'

# Force logger mode before loading anything
ENV['EMAILER_MODE'] = 'logger'

# Load the app - this will use EMAILER_MODE from ENV in ERB template
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

# Force config reload to pick up EMAILER_MODE env var
Onetime::Config.load

# Reset mailer to ensure clean state with new config
Onetime::Mail::Mailer.reset!

require 'ostruct'

# Setup test data
@mock_secret = OpenStruct.new(key: 'pipeline_test_key_123', share_domain: nil)
@recipient = 'tryouts+recipient@onetimesecret.com'
@sender = 'tryouts+sender@onetimesecret.com'

# TRYOUTS

## Mailer.delivery_backend returns Logger in test environment
Onetime::Mail::Mailer.delivery_backend.class
#=> Onetime::Mail::Delivery::Logger

## Mailer.from_address returns configured or default from address
Onetime::Mail::Mailer.from_address.nil?
#=> false

## Mailer.from_address is a string
Onetime::Mail::Mailer.from_address.class
#=> String

## Mailer.reset! clears cached backend
backend1 = Onetime::Mail::Mailer.delivery_backend
Onetime::Mail::Mailer.reset!
backend2 = Onetime::Mail::Mailer.delivery_backend
backend1.object_id == backend2.object_id
#=> false

## Mailer.deliver with :secret_link returns success
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver(:secret_link, {
  secret: @mock_secret,
  recipient: @recipient,
  sender_email: @sender
}, locale: 'en')
result[:status]
#=> 'logged'

## Mailer.deliver with :secret_link returns correct recipient
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver(:secret_link, {
  secret: @mock_secret,
  recipient: @recipient,
  sender_email: @sender
})
result[:to]
#=> @recipient

## Mailer.deliver_template accepts template instance
Onetime::Mail::Mailer.reset!
template = Onetime::Mail::Templates::SecretLink.new({
  secret: @mock_secret,
  recipient: @recipient,
  sender_email: @sender
})
result = Onetime::Mail::Mailer.deliver_template(template)
result[:status]
#=> 'logged'

## Mailer.deliver_raw sends normalized email hash
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver_raw({
  to: @recipient,
  from: 'test@example.com',
  subject: 'Test Subject',
  body: 'Test body content'
})
result[:status]
#=> 'logged'

## Mailer.deliver_raw handles formatted from address
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver_raw({
  to: @recipient,
  from: 'Test Sender <test@example.com>',
  subject: 'Test Subject',
  body: 'Test body content'
})
result[:status]
#=> 'logged'

## Mailer.deliver with :welcome template works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver(:welcome, {
  email_address: @recipient,
  secret: @mock_secret
})
result[:status]
#=> 'logged'

## Mailer.deliver with :password_request template works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver(:password_request, {
  email_address: @recipient,
  secret: @mock_secret
})
result[:status]
#=> 'logged'

## Mailer.deliver with :incoming_secret template works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail::Mailer.deliver(:incoming_secret, {
  secret: @mock_secret,
  recipient: @recipient,
  memo: 'Test memo'
})
result[:status]
#=> 'logged'

## Mailer.deliver with unknown template raises ArgumentError
Onetime::Mail::Mailer.reset!
begin
  Onetime::Mail::Mailer.deliver(:unknown_template, {})
rescue ArgumentError => e
  e.message
end
#=> 'Unknown template: unknown_template'

## Convenience method Onetime::Mail.deliver works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail.deliver(:secret_link, {
  secret: @mock_secret,
  recipient: @recipient,
  sender_email: @sender
})
result[:status]
#=> 'logged'

## Convenience method Onetime::Mail.deliver_raw works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail.deliver_raw({
  to: @recipient,
  from: 'test@example.com',
  subject: 'Raw email',
  body: 'Body'
})
result[:status]
#=> 'logged'
