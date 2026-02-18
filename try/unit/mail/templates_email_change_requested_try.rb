# try/unit/mail/templates_email_change_requested_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::EmailChangeRequested class.
#
# EmailChangeRequested is a security notification sent to OLD email when
# an email change is requested (before confirmation).
# Required data: old_email, new_email
# Optional: requested_at, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/email_change_requested'

@valid_data = {
  old_email: 'olduser@example.com',
  new_email: 'newuser@example.com'
}

# TRYOUTS

## EmailChangeRequested validates presence of old_email
begin
  Onetime::Mail::Templates::EmailChangeRequested.new({
    new_email: 'newuser@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Old email required'

## EmailChangeRequested validates presence of new_email
begin
  Onetime::Mail::Templates::EmailChangeRequested.new({
    old_email: 'olduser@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'New email required'

## EmailChangeRequested accepts valid data without error
template = Onetime::Mail::Templates::EmailChangeRequested.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::EmailChangeRequested

## EmailChangeRequested recipient_email returns old_email from data
template = Onetime::Mail::Templates::EmailChangeRequested.new(@valid_data)
template.recipient_email
#=> 'olduser@example.com'

## EmailChangeRequested old_email returns data value
template = Onetime::Mail::Templates::EmailChangeRequested.new(@valid_data)
template.old_email
#=> 'olduser@example.com'

## EmailChangeRequested new_email returns full email address
template = Onetime::Mail::Templates::EmailChangeRequested.new(@valid_data)
template.new_email
#=> 'newuser@example.com'

## EmailChangeRequested requested_at returns provided value when given
data = @valid_data.merge(requested_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::EmailChangeRequested.new(data)
template.requested_at
#=> '2024-01-15T10:30:00Z'

## EmailChangeRequested requested_at_formatted returns human-readable date
data = @valid_data.merge(requested_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::EmailChangeRequested.new(data)
template.requested_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## EmailChangeRequested support_path returns feedback path with reason param
template = Onetime::Mail::Templates::EmailChangeRequested.new(@valid_data)
template.support_path
#=> '/feedback?reason=email_change_unauthorized'

## EmailChangeRequested baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::EmailChangeRequested.new(data)
template.baseuri
#=> 'https://custom.example.com'

## EmailChangeRequested subject returns a non-empty string
template = Onetime::Mail::Templates::EmailChangeRequested.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
