# try/unit/mail/templates_role_changed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::RoleChanged class.
#
# RoleChanged is a notification sent when a member's role is changed in an organization.
# Required data: email_address, organization_name, old_role, new_role
# Optional: changed_by, changed_at, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/role_changed'

@valid_data = {
  email_address: 'member@example.com',
  organization_name: 'Acme Corp',
  old_role: 'member',
  new_role: 'admin'
}

# TRYOUTS

## RoleChanged validates presence of email_address
begin
  Onetime::Mail::Templates::RoleChanged.new({
    organization_name: 'Acme Corp',
    old_role: 'member',
    new_role: 'admin'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## RoleChanged validates presence of organization_name
begin
  Onetime::Mail::Templates::RoleChanged.new({
    email_address: 'member@example.com',
    old_role: 'member',
    new_role: 'admin'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Organization name required'

## RoleChanged validates presence of old_role
begin
  Onetime::Mail::Templates::RoleChanged.new({
    email_address: 'member@example.com',
    organization_name: 'Acme Corp',
    new_role: 'admin'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Old role required'

## RoleChanged validates presence of new_role
begin
  Onetime::Mail::Templates::RoleChanged.new({
    email_address: 'member@example.com',
    organization_name: 'Acme Corp',
    old_role: 'member'
  })
rescue ArgumentError => e
  e.message
end
#=> 'New role required'

## RoleChanged accepts valid data without error
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::RoleChanged

## RoleChanged recipient_email returns email_address from data
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.recipient_email
#=> 'member@example.com'

## RoleChanged organization_name returns data value
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.organization_name
#=> 'Acme Corp'

## RoleChanged old_role returns data value
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.old_role
#=> 'member'

## RoleChanged new_role returns data value
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.new_role
#=> 'admin'

## RoleChanged changed_by returns data value when provided
data = @valid_data.merge(changed_by: 'owner@example.com')
template = Onetime::Mail::Templates::RoleChanged.new(data)
template.changed_by
#=> 'owner@example.com'

## RoleChanged changed_by returns nil when not provided
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.changed_by
#=> nil

## RoleChanged changed_at returns provided value when given
data = @valid_data.merge(changed_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::RoleChanged.new(data)
template.changed_at
#=> '2024-01-15T10:30:00Z'

## RoleChanged changed_at_formatted returns human-readable date
data = @valid_data.merge(changed_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::RoleChanged.new(data)
template.changed_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## RoleChanged organization_settings_path returns expected path
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.organization_settings_path
#=> '/account/organizations'

## RoleChanged baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::RoleChanged.new(data)
template.baseuri
#=> 'https://custom.example.com'

## RoleChanged subject returns a non-empty string
template = Onetime::Mail::Templates::RoleChanged.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
