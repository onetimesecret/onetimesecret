# try/unit/mail/templates_mfa_disabled_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::MfaDisabled class.
#
# MfaDisabled is a security notification sent when two-factor authentication is disabled.
# Required data: email_address, disabled_at
# Optional: baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/mfa_disabled'

@valid_data = {
  email_address: 'user@example.com',
  disabled_at: '2024-01-15T10:30:00Z'
}

# TRYOUTS

## MfaDisabled validates presence of email_address
begin
  Onetime::Mail::Templates::MfaDisabled.new({
    disabled_at: '2024-01-15T10:30:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## MfaDisabled validates presence of disabled_at
begin
  Onetime::Mail::Templates::MfaDisabled.new({
    email_address: 'test@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Disabled at timestamp required'

## MfaDisabled accepts valid data without error
template = Onetime::Mail::Templates::MfaDisabled.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::MfaDisabled

## MfaDisabled recipient_email returns email_address from data
template = Onetime::Mail::Templates::MfaDisabled.new(@valid_data)
template.recipient_email
#=> 'user@example.com'

## MfaDisabled disabled_at returns data value
template = Onetime::Mail::Templates::MfaDisabled.new(@valid_data)
template.disabled_at
#=> '2024-01-15T10:30:00Z'

## MfaDisabled disabled_at_formatted returns human-readable date
template = Onetime::Mail::Templates::MfaDisabled.new(@valid_data)
template.disabled_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## MfaDisabled security_settings_path returns expected path
template = Onetime::Mail::Templates::MfaDisabled.new(@valid_data)
template.security_settings_path
#=> '/account/settings/profile/security'

## MfaDisabled baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::MfaDisabled.new(data)
template.baseuri
#=> 'https://custom.example.com'

## MfaDisabled subject returns a non-empty string
template = Onetime::Mail::Templates::MfaDisabled.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
