# try/unit/mail/templates_incoming_secret_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::IncomingSecret class.
#
# IncomingSecret is used for incoming secrets feature notifications.
# Required data: secret_key, recipient
# Optional: share_domain, memo, baseuri
#
# NOTE: Uses primitive data types for RabbitMQ serialization.
# Secret objects cannot be serialized to JSON.

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

@valid_data = {
  secret_key: 'incoming_key_abc',
  recipient: 'recipient@example.com'
}

# TRYOUTS

## IncomingSecret validates presence of secret_key
begin
  Onetime::Mail::Templates::IncomingSecret.new({
    recipient: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret key required'

## IncomingSecret validates presence of recipient
begin
  Onetime::Mail::Templates::IncomingSecret.new({
    secret_key: 'abc123'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Recipient required'

## IncomingSecret accepts valid data without error
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::IncomingSecret

## IncomingSecret subject is generic (security - no memo in subject)
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.subject
#=> "You've received a secret message"

## IncomingSecret recipient_email returns recipient from data
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.recipient_email
#=> 'recipient@example.com'

## IncomingSecret uri_path includes secret key
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.uri_path
#=> '/secret/incoming_key_abc'

## IncomingSecret memo returns nil when not provided
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.memo
#=> nil

## IncomingSecret has_memo? returns false when no memo
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.has_memo?
#=> false

## IncomingSecret memo returns data value when provided
data = @valid_data.merge(memo: 'Important info')
template = Onetime::Mail::Templates::IncomingSecret.new(data)
template.memo
#=> 'Important info'

## IncomingSecret has_memo? returns true when memo present
data = @valid_data.merge(memo: 'Important info')
template = Onetime::Mail::Templates::IncomingSecret.new(data)
template.has_memo?
#=> true

## IncomingSecret has_memo? returns false for empty memo
data = @valid_data.merge(memo: '')
template = Onetime::Mail::Templates::IncomingSecret.new(data)
template.has_memo?
#=> false

## IncomingSecret display_domain uses site host by default
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.display_domain
#=~> /https?:\/\/.+/

## IncomingSecret display_domain uses share_domain when present
data = @valid_data.merge(share_domain: 'custom.example.com')
template = Onetime::Mail::Templates::IncomingSecret.new(data)
template.display_domain
#=~> /https?:\/\/custom\.example\.com/

## IncomingSecret signature_link returns site baseuri
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.signature_link
#=~> /https?:\/\/.+/

## IncomingSecret baseuri respects data override
data = @valid_data.merge(baseuri: 'https://override.example.com')
template = Onetime::Mail::Templates::IncomingSecret.new(data)
template.baseuri
#=> 'https://override.example.com'

## IncomingSecret render_text returns string with secret link
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
template.render_text.include?('/secret/incoming_key_abc')
#=> true

## IncomingSecret to_email returns complete hash
template = Onetime::Mail::Templates::IncomingSecret.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
[email[:to], email[:subject].include?('secret')]
#=> ['recipient@example.com', true]
