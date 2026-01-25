# try/unit/mail/templates_secret_link_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::SecretLink class.
#
# SecretLink is used when sharing a secret link via email.
# Required data: secret_key, recipient, sender_email
# Optional: share_domain, baseuri
#
# NOTE: Uses primitive data types for RabbitMQ serialization.
# Secret objects cannot be serialized to JSON.

require_relative '../../support/test_helpers'

# Load the app to get templates and config
OT.boot! :test, false

# Load the mail module explicitly
require 'onetime/mail'

@valid_data = {
  secret_key: 'abc123def456',
  share_domain: nil,
  recipient: 'recipient@example.com',
  sender_email: 'sender@example.com'
}

@valid_data_with_domain = {
  secret_key: 'xyz789',
  share_domain: 'custom.example.com',
  recipient: 'recipient@example.com',
  sender_email: 'sender@example.com'
}

# TRYOUTS

## SecretLink validates presence of secret_key
begin
  Onetime::Mail::Templates::SecretLink.new({
    recipient: 'test@example.com',
    sender_email: 'sender@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret key required'

## SecretLink validates presence of recipient
begin
  Onetime::Mail::Templates::SecretLink.new({
    secret_key: 'abc123',
    sender_email: 'sender@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Recipient required'

## SecretLink validates presence of sender_email
begin
  Onetime::Mail::Templates::SecretLink.new({
    secret_key: 'abc123',
    recipient: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Sender email required'

## SecretLink accepts valid data without error
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::SecretLink

## SecretLink subject includes sender email
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.subject
#=> 'sender@example.com sent you a secret'

## SecretLink recipient_email returns recipient from data
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.recipient_email
#=> 'recipient@example.com'

## SecretLink uri_path includes secret key
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.uri_path
#=> '/secret/abc123def456'

## SecretLink custid returns sender_email
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.custid
#=> 'sender@example.com'

## SecretLink display_domain uses site host by default
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.display_domain
#=~> /https?:\/\/.+/

## SecretLink display_domain uses share_domain when present
template = Onetime::Mail::Templates::SecretLink.new(@valid_data_with_domain)
template.display_domain
#=~> /https?:\/\/custom\.example\.com/

## SecretLink baseuri uses site config by default
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.baseuri
#=~> /https?:\/\/.+/

## SecretLink baseuri respects data override
data = @valid_data.merge(baseuri: 'https://override.example.com')
template = Onetime::Mail::Templates::SecretLink.new(data)
template.baseuri
#=> 'https://override.example.com'

## SecretLink signature_link returns site baseuri
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.signature_link
#=~> /https?:\/\/.+/

## SecretLink render_text returns string
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.render_text.class
#=> String

## SecretLink render_text contains secret URI
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
template.render_text.include?('/secret/abc123def456')
#=> true

## SecretLink render_html returns string or nil
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
result = template.render_html
result.nil? || result.is_a?(String)
#=> true

## SecretLink to_email returns complete email hash
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
[email[:to], email[:from], email[:subject].include?('sent you a secret')]
#=> ['recipient@example.com', 'noreply@example.com', true]

## SecretLink to_email includes text_body
template = Onetime::Mail::Templates::SecretLink.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
email[:text_body].is_a?(String) && !email[:text_body].empty?
#=> true

## SecretLink handles nil share_domain gracefully
data = @valid_data.merge(share_domain: nil)
template = Onetime::Mail::Templates::SecretLink.new(data)
template.display_domain
#=~> /https?:\/\/.+/
