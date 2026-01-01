# try/unit/mail/templates_secret_revealed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::SecretRevealed class.
#
# SecretRevealed is sent to secret owners when their secret is viewed.
# Required data: recipient, secret_shortid
# Optional: revealed_at, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

@valid_data = {
  recipient: 'owner@example.com',
  secret_shortid: 'abc123'
}

@valid_data_with_timestamp = {
  recipient: 'owner@example.com',
  secret_shortid: 'xyz789',
  revealed_at: '2024-06-15T14:30:00Z'
}

# TRYOUTS

## SecretRevealed validates presence of recipient
begin
  Onetime::Mail::Templates::SecretRevealed.new({
    secret_shortid: 'abc123'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Recipient email required'

## SecretRevealed validates presence of secret_shortid
begin
  Onetime::Mail::Templates::SecretRevealed.new({
    recipient: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret shortid required'

## SecretRevealed accepts valid data without error
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::SecretRevealed

## SecretRevealed subject uses EmailTranslations.translate
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.subject
#=> 'Your secret was viewed'

## SecretRevealed recipient_email returns recipient from data
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.recipient_email
#=> 'owner@example.com'

## SecretRevealed secret_shortid returns value from data
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.secret_shortid
#=> 'abc123'

## SecretRevealed revealed_at defaults to current time when not provided
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.revealed_at
#=~> /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

## SecretRevealed revealed_at uses provided timestamp
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data_with_timestamp)
template.revealed_at
#=> '2024-06-15T14:30:00Z'

## SecretRevealed revealed_at_formatted formats date correctly
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data_with_timestamp)
template.revealed_at_formatted
#=> 'June 15, 2024 at 14:30 UTC'

## SecretRevealed settings_path returns notification settings path
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.settings_path
#=> '/account/settings/profile/notifications'

## SecretRevealed baseuri uses site config by default
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.baseuri
#=~> /https?:\/\/.+/

## SecretRevealed baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::SecretRevealed.new(data)
template.baseuri
#=> 'https://custom.example.com'

## SecretRevealed render_text returns string
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.render_text.class
#=> String

## SecretRevealed render_text contains shortid
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.render_text.include?('abc123')
#=> true

## SecretRevealed render_text contains timestamp info
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data_with_timestamp)
template.render_text.include?('June 15, 2024')
#=> true

## SecretRevealed render_html returns a String
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
template.render_html.class
#=> String

## SecretRevealed to_email returns complete hash with all required keys
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
[email[:to], email[:from], email.key?(:subject), email.key?(:text_body)]
#=> ['owner@example.com', 'noreply@example.com', true, true]

## SecretRevealed to_email includes text_body
template = Onetime::Mail::Templates::SecretRevealed.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
email[:text_body].is_a?(String) && !email[:text_body].empty?
#=> true
