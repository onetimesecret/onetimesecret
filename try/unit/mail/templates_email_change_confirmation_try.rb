# try/unit/mail/templates_email_change_confirmation_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::EmailChangeConfirmation class.
#
# EmailChangeConfirmation is a verification email sent to NEW email address for confirmation.
# Required data: new_email, confirmation_token
# Optional: expires_in_hours, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/email_change_confirmation'

@valid_data = {
  new_email: 'newuser@example.com',
  confirmation_token: 'abc123def456'
}

# TRYOUTS

## EmailChangeConfirmation validates presence of new_email
begin
  Onetime::Mail::Templates::EmailChangeConfirmation.new({
    confirmation_token: 'abc123def456'
  })
rescue ArgumentError => e
  e.message
end
#=> 'New email required'

## EmailChangeConfirmation validates presence of confirmation_token
begin
  Onetime::Mail::Templates::EmailChangeConfirmation.new({
    new_email: 'newuser@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Confirmation token required'

## EmailChangeConfirmation accepts valid data without error
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::EmailChangeConfirmation

## EmailChangeConfirmation recipient_email returns new_email from data
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.recipient_email
#=> 'newuser@example.com'

## EmailChangeConfirmation new_email returns data value
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.new_email
#=> 'newuser@example.com'

## EmailChangeConfirmation confirmation_token returns data value
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.confirmation_token
#=> 'abc123def456'

## EmailChangeConfirmation confirmation_uri includes token
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.confirmation_uri.include?('abc123def456')
#=> true

## EmailChangeConfirmation confirmation_uri has correct path structure
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.confirmation_uri.include?('/account/email/confirm/')
#=> true

## EmailChangeConfirmation expires_in_hours defaults to 24
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.expires_in_hours
#=> 24

## EmailChangeConfirmation expires_in_hours respects custom value
data = @valid_data.merge(expires_in_hours: 48)
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(data)
template.expires_in_hours
#=> 48

## EmailChangeConfirmation baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(data)
template.baseuri
#=> 'https://custom.example.com'

## EmailChangeConfirmation subject returns a non-empty string
template = Onetime::Mail::Templates::EmailChangeConfirmation.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
