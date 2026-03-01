# try/unit/mail/templates_email_changed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::EmailChanged class.
#
# EmailChanged is a security notification sent to OLD email after email change is confirmed.
# Required data: old_email, new_email
# Optional: changed_at, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/email_changed'

@valid_data = {
  old_email: 'olduser@example.com',
  new_email: 'newuser@example.com'
}

# TRYOUTS

## EmailChanged validates presence of old_email
begin
  Onetime::Mail::Templates::EmailChanged.new({
    new_email: 'newuser@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Old email required'

## EmailChanged validates presence of new_email
begin
  Onetime::Mail::Templates::EmailChanged.new({
    old_email: 'olduser@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'New email required'

## EmailChanged accepts valid data without error
template = Onetime::Mail::Templates::EmailChanged.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::EmailChanged

## EmailChanged recipient_email returns old_email from data
template = Onetime::Mail::Templates::EmailChanged.new(@valid_data)
template.recipient_email
#=> 'olduser@example.com'

## EmailChanged old_email returns data value
template = Onetime::Mail::Templates::EmailChanged.new(@valid_data)
template.old_email
#=> 'olduser@example.com'

## EmailChanged new_email returns full email address
template = Onetime::Mail::Templates::EmailChanged.new(@valid_data)
template.new_email
#=> 'newuser@example.com'

## EmailChanged changed_at returns provided value when given
data = @valid_data.merge(changed_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::EmailChanged.new(data)
template.changed_at
#=> '2024-01-15T10:30:00Z'

## EmailChanged changed_at_formatted returns human-readable date
data = @valid_data.merge(changed_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::EmailChanged.new(data)
template.changed_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## EmailChanged support_path returns expected path
template = Onetime::Mail::Templates::EmailChanged.new(@valid_data)
template.support_path
#=> '/feedback?reason=email_change_unauthorized'

## EmailChanged baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::EmailChanged.new(data)
template.baseuri
#=> 'https://custom.example.com'

## EmailChanged subject returns a non-empty string
template = Onetime::Mail::Templates::EmailChanged.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
