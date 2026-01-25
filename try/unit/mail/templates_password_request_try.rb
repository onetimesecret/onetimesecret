# try/unit/mail/templates_password_request_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PasswordRequest class.
#
# PasswordRequest is used for password reset emails.
# Required data: email_address, plus either reset_password_path (full mode) or secret (simple mode)
# Optional: baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

# Data class for mocking secrets (immutable, Ruby 3.2+)
# Uses identifier (not deprecated .key field)
MockPasswordSecret = Data.define(:identifier)

# Setup mock secret
@mock_secret = MockPasswordSecret.new(identifier: 'password_reset_key_789')

@valid_data = {
  email_address: 'user@example.com',
  secret: @mock_secret
}

# TRYOUTS

## PasswordRequest validates presence of email_address
begin
  Onetime::Mail::Templates::PasswordRequest.new({
    secret: @mock_secret
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## PasswordRequest validates presence of reset_password_path or secret
begin
  Onetime::Mail::Templates::PasswordRequest.new({
    email_address: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Reset password path or secret required'

## PasswordRequest accepts valid data without error
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::PasswordRequest

## PasswordRequest subject uses dynamic display_domain
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.subject.start_with?('Reset your password')
#=> true

## PasswordRequest recipient_email returns email_address from data
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.recipient_email
#=> 'user@example.com'

## PasswordRequest forgot_path includes secret key
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.forgot_path
#=> '/forgot/password_reset_key_789'

## PasswordRequest email_address returns data value
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.email_address
#=> 'user@example.com'

## PasswordRequest baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::PasswordRequest.new(data)
template.baseuri
#=> 'https://custom.example.com'

## PasswordRequest render_text returns string with forgot link
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.render_text.include?('/forgot/password_reset_key_789')
#=> true

## PasswordRequest to_email returns complete hash
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
[email[:to], email[:subject].include?('password')]
#=> ['user@example.com', true]

## PasswordRequest accepts reset_password_path for full mode (Rodauth)
@full_mode_data = {
  email_address: 'user@example.com',
  reset_password_path: 'https://example.com/auth/reset-password?key=abc123'
}
template = Onetime::Mail::Templates::PasswordRequest.new(@full_mode_data)
template.reset_password_url
#=> 'https://example.com/auth/reset-password?key=abc123'

## PasswordRequest forgot_path is empty in full mode
template = Onetime::Mail::Templates::PasswordRequest.new(@full_mode_data)
template.forgot_path
#=> ''
