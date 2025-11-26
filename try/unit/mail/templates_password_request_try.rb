# try/unit/mail/templates_password_request_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PasswordRequest class.
#
# PasswordRequest is used for password reset emails.
# Required data: email_address, secret
# Optional: baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

require 'ostruct'

# Setup mock secret
@mock_secret = OpenStruct.new(key: 'password_reset_key_789')

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

## PasswordRequest validates presence of secret
begin
  Onetime::Mail::Templates::PasswordRequest.new({
    email_address: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret required'

## PasswordRequest accepts valid data without error
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::PasswordRequest

## PasswordRequest subject mentions password reset
template = Onetime::Mail::Templates::PasswordRequest.new(@valid_data)
template.subject
#=> 'Reset your password (OnetimeSecret.com)'

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
