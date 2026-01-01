# try/unit/mail/templates_new_login_alert_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::NewLoginAlert class.
#
# NewLoginAlert is a security alert sent when a new sign-in is detected.
# Required data: email_address, device_info, location, login_at
# Optional: ip_address, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/templates/new_login_alert'

@valid_data = {
  email_address: 'user@example.com',
  device_info: 'Chrome on macOS',
  location: 'San Francisco, CA, USA',
  login_at: '2024-01-15T10:30:00Z'
}

# TRYOUTS

## NewLoginAlert validates presence of email_address
begin
  Onetime::Mail::Templates::NewLoginAlert.new({
    device_info: 'Chrome on macOS',
    location: 'San Francisco, CA, USA',
    login_at: '2024-01-15T10:30:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## NewLoginAlert validates presence of device_info
begin
  Onetime::Mail::Templates::NewLoginAlert.new({
    email_address: 'user@example.com',
    location: 'San Francisco, CA, USA',
    login_at: '2024-01-15T10:30:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Device info required'

## NewLoginAlert validates presence of location
begin
  Onetime::Mail::Templates::NewLoginAlert.new({
    email_address: 'user@example.com',
    device_info: 'Chrome on macOS',
    login_at: '2024-01-15T10:30:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Location required'

## NewLoginAlert validates presence of login_at
begin
  Onetime::Mail::Templates::NewLoginAlert.new({
    email_address: 'user@example.com',
    device_info: 'Chrome on macOS',
    location: 'San Francisco, CA, USA'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Login at timestamp required'

## NewLoginAlert accepts valid data without error
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::NewLoginAlert

## NewLoginAlert recipient_email returns email_address from data
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.recipient_email
#=> 'user@example.com'

## NewLoginAlert device_info returns data value
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.device_info
#=> 'Chrome on macOS'

## NewLoginAlert location returns data value
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.location
#=> 'San Francisco, CA, USA'

## NewLoginAlert login_at returns data value
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.login_at
#=> '2024-01-15T10:30:00Z'

## NewLoginAlert login_at_formatted returns human-readable date
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.login_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## NewLoginAlert ip_address returns data value when provided
data = @valid_data.merge(ip_address: '192.168.1.1')
template = Onetime::Mail::Templates::NewLoginAlert.new(data)
template.ip_address
#=> '192.168.1.1'

## NewLoginAlert ip_address returns nil when not provided
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.ip_address
#=> nil

## NewLoginAlert security_settings_path returns expected path
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.security_settings_path
#=> '/account/settings/profile/security'

## NewLoginAlert support_path returns expected path
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.support_path
#=> '/support'

## NewLoginAlert baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::NewLoginAlert.new(data)
template.baseuri
#=> 'https://custom.example.com'

## NewLoginAlert subject returns a non-empty string
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
