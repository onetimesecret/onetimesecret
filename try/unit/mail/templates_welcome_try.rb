# try/unit/mail/templates_welcome_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::Welcome class.
#
# Welcome is used for new user verification emails.
# Required data: email_address, secret
# Optional: baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

require 'ostruct'

# Setup mock secret - responds to :identifier method like real Secret objects
@mock_secret = OpenStruct.new(identifier: 'welcome_verify_key_456')

@valid_data = {
  email_address: 'newuser@example.com',
  secret: @mock_secret
}

# TRYOUTS

## Welcome validates presence of email_address
begin
  Onetime::Mail::Templates::Welcome.new({
    secret: @mock_secret
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## Welcome validates presence of secret
begin
  Onetime::Mail::Templates::Welcome.new({
    email_address: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret required'

## Welcome accepts valid data without error
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::Welcome

## Welcome subject is verification message
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
template.subject
#=> 'Welcome to Onetime Secret - Please verify your email'

## Welcome recipient_email returns email_address from data
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
template.recipient_email
#=> 'newuser@example.com'

## Welcome verify_uri includes secret key
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
template.verify_uri
#=> '/secret/welcome_verify_key_456'

## Welcome email_address returns data value
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
template.email_address
#=> 'newuser@example.com'

## Welcome baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::Welcome.new(data)
template.baseuri
#=> 'https://custom.example.com'

## Welcome render_text returns string with verify link
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
template.render_text.include?('/secret/welcome_verify_key_456')
#=> true

## Welcome to_email returns complete hash
template = Onetime::Mail::Templates::Welcome.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
[email[:to], email[:subject].include?('verify')]
#=> ['newuser@example.com', true]
