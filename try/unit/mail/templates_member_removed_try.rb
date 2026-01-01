# try/unit/mail/templates_member_removed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::MemberRemoved class.
#
# MemberRemoved is a notification sent when a member is removed from an organization.
# Required data: email_address, organization_name, removed_by
# Optional: removed_at, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/templates/member_removed'

@valid_data = {
  email_address: 'member@example.com',
  organization_name: 'Acme Corp',
  removed_by: 'admin@example.com'
}

# TRYOUTS

## MemberRemoved validates presence of email_address
begin
  Onetime::Mail::Templates::MemberRemoved.new({
    organization_name: 'Acme Corp',
    removed_by: 'admin@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## MemberRemoved validates presence of organization_name
begin
  Onetime::Mail::Templates::MemberRemoved.new({
    email_address: 'member@example.com',
    removed_by: 'admin@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Organization name required'

## MemberRemoved validates presence of removed_by
begin
  Onetime::Mail::Templates::MemberRemoved.new({
    email_address: 'member@example.com',
    organization_name: 'Acme Corp'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Removed by required'

## MemberRemoved accepts valid data without error
template = Onetime::Mail::Templates::MemberRemoved.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::MemberRemoved

## MemberRemoved recipient_email returns email_address from data
template = Onetime::Mail::Templates::MemberRemoved.new(@valid_data)
template.recipient_email
#=> 'member@example.com'

## MemberRemoved organization_name returns data value
template = Onetime::Mail::Templates::MemberRemoved.new(@valid_data)
template.organization_name
#=> 'Acme Corp'

## MemberRemoved removed_by returns data value
template = Onetime::Mail::Templates::MemberRemoved.new(@valid_data)
template.removed_by
#=> 'admin@example.com'

## MemberRemoved removed_at returns provided value when given
data = @valid_data.merge(removed_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::MemberRemoved.new(data)
template.removed_at
#=> '2024-01-15T10:30:00Z'

## MemberRemoved removed_at_formatted returns human-readable date
data = @valid_data.merge(removed_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::MemberRemoved.new(data)
template.removed_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## MemberRemoved support_path returns expected path
template = Onetime::Mail::Templates::MemberRemoved.new(@valid_data)
template.support_path
#=> '/support'

## MemberRemoved baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::MemberRemoved.new(data)
template.baseuri
#=> 'https://custom.example.com'

## MemberRemoved subject returns a non-empty string
template = Onetime::Mail::Templates::MemberRemoved.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
