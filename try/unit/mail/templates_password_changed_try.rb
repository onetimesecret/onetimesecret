# try/unit/mail/templates_password_changed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PasswordChanged class.
#
# PasswordChanged is a security notification sent when a user's password is changed.
# Required data: email_address, changed_at
# Optional: baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/templates/password_changed'

@valid_data = {
  email_address: 'user@example.com',
  changed_at: '2024-01-15T10:30:00Z'
}

# TRYOUTS

## PasswordChanged validates presence of email_address
begin
  Onetime::Mail::Templates::PasswordChanged.new({
    changed_at: '2024-01-15T10:30:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## PasswordChanged validates presence of changed_at
begin
  Onetime::Mail::Templates::PasswordChanged.new({
    email_address: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Changed at timestamp required'

## PasswordChanged accepts valid data without error
template = Onetime::Mail::Templates::PasswordChanged.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::PasswordChanged

## PasswordChanged recipient_email returns email_address from data
template = Onetime::Mail::Templates::PasswordChanged.new(@valid_data)
template.recipient_email
#=> 'user@example.com'

## PasswordChanged changed_at returns data value
template = Onetime::Mail::Templates::PasswordChanged.new(@valid_data)
template.changed_at
#=> '2024-01-15T10:30:00Z'

## PasswordChanged changed_at_formatted returns human-readable date
template = Onetime::Mail::Templates::PasswordChanged.new(@valid_data)
template.changed_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## PasswordChanged security_settings_path returns expected path
template = Onetime::Mail::Templates::PasswordChanged.new(@valid_data)
template.security_settings_path
#=> '/account/settings/profile/security'

## PasswordChanged baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::PasswordChanged.new(data)
template.baseuri
#=> 'https://custom.example.com'

## PasswordChanged subject returns a non-empty string
template = Onetime::Mail::Templates::PasswordChanged.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
