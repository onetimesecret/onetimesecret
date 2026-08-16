# try/unit/mail/templates_new_login_alert_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::NewLoginAlert class.
#
# NewLoginAlert is a security alert sent when a new sign-in is detected.
# Required data: email_address, device_info, location, login_at
# Optional: baseuri
#
# location is whatever Auth::Operations::ResolveLoginLocation produced: an
# ISO 3166-1 alpha-2 country code, an already-masked client IP, or the literal
# 'Unknown location'. The view passes it through untouched, so the fixtures
# below use those three shapes only — a city string is not a possible input.

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/new_login_alert'

@valid_data = {
  email_address: 'user@example.com',
  device_info: 'Chrome on macOS',
  location: 'US',
  login_at: '2024-01-15T10:30:00Z'
}

# TRYOUTS

## NewLoginAlert validates presence of email_address
begin
  Onetime::Mail::Templates::NewLoginAlert.new({
    device_info: 'Chrome on macOS',
    location: 'US',
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
    location: 'US',
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
    location: 'US'
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

## NewLoginAlert location passes through a country code
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.location
#=> 'US'

## NewLoginAlert location passes through a masked IP fallback
data = @valid_data.merge(location: '203.0.113.0')
template = Onetime::Mail::Templates::NewLoginAlert.new(data)
template.location
#=> '203.0.113.0'

## NewLoginAlert location passes through the unknown-location fallback
data = @valid_data.merge(location: 'Unknown location')
template = Onetime::Mail::Templates::NewLoginAlert.new(data)
template.location
#=> 'Unknown location'

## NewLoginAlert login_at returns data value
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.login_at
#=> '2024-01-15T10:30:00Z'

## NewLoginAlert login_at_formatted returns human-readable date
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.login_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## NewLoginAlert exposes no ip_address accessor
# The field was removed so no caller can put a raw IP in this email; the
# sign-in origin travels only through location.
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.respond_to?(:ip_address)
#=> false

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

## NewLoginAlert subject interpolates display_domain (no raw placeholder)
template = Onetime::Mail::Templates::NewLoginAlert.new(@valid_data)
template.subject.include?('%{')
#=> false
