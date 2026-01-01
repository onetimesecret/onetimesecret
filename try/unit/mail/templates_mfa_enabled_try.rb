# try/unit/mail/templates_mfa_enabled_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::MfaEnabled class.
#
# MfaEnabled is a security notification sent when two-factor authentication is enabled.
# Required data: email_address, enabled_at
# Optional: baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/templates/mfa_enabled'

@valid_data = {
  email_address: 'user@example.com',
  enabled_at: '2024-01-15T10:30:00Z'
}

# TRYOUTS

## MfaEnabled validates presence of email_address
begin
  Onetime::Mail::Templates::MfaEnabled.new({
    enabled_at: '2024-01-15T10:30:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## MfaEnabled validates presence of enabled_at
begin
  Onetime::Mail::Templates::MfaEnabled.new({
    email_address: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Enabled at timestamp required'

## MfaEnabled accepts valid data without error
template = Onetime::Mail::Templates::MfaEnabled.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::MfaEnabled

## MfaEnabled recipient_email returns email_address from data
template = Onetime::Mail::Templates::MfaEnabled.new(@valid_data)
template.recipient_email
#=> 'user@example.com'

## MfaEnabled enabled_at returns data value
template = Onetime::Mail::Templates::MfaEnabled.new(@valid_data)
template.enabled_at
#=> '2024-01-15T10:30:00Z'

## MfaEnabled enabled_at_formatted returns human-readable date
template = Onetime::Mail::Templates::MfaEnabled.new(@valid_data)
template.enabled_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## MfaEnabled security_settings_path returns expected path
template = Onetime::Mail::Templates::MfaEnabled.new(@valid_data)
template.security_settings_path
#=> '/account/settings/profile/security'

## MfaEnabled baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::MfaEnabled.new(data)
template.baseuri
#=> 'https://custom.example.com'

## MfaEnabled subject returns a non-empty string
template = Onetime::Mail::Templates::MfaEnabled.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
