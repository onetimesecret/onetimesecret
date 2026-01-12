# try/unit/mail/templates_organization_deleted_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::OrganizationDeleted class.
#
# OrganizationDeleted is a notification sent to all members when an organization is deleted.
# Required data: email_address, organization_name, deleted_by
# Optional: deleted_at, baseuri

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/organization_deleted'

@valid_data = {
  email_address: 'member@example.com',
  organization_name: 'Acme Corp',
  deleted_by: 'owner@example.com'
}

# TRYOUTS

## OrganizationDeleted validates presence of email_address
begin
  Onetime::Mail::Templates::OrganizationDeleted.new({
    organization_name: 'Acme Corp',
    deleted_by: 'owner@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## OrganizationDeleted validates presence of organization_name
begin
  Onetime::Mail::Templates::OrganizationDeleted.new({
    email_address: 'member@example.com',
    deleted_by: 'owner@example.com'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Organization name required'

## OrganizationDeleted validates presence of deleted_by
begin
  Onetime::Mail::Templates::OrganizationDeleted.new({
    email_address: 'member@example.com',
    organization_name: 'Acme Corp'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Deleted by required'

## OrganizationDeleted accepts valid data without error
template = Onetime::Mail::Templates::OrganizationDeleted.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::OrganizationDeleted

## OrganizationDeleted recipient_email returns email_address from data
template = Onetime::Mail::Templates::OrganizationDeleted.new(@valid_data)
template.recipient_email
#=> 'member@example.com'

## OrganizationDeleted organization_name returns data value
template = Onetime::Mail::Templates::OrganizationDeleted.new(@valid_data)
template.organization_name
#=> 'Acme Corp'

## OrganizationDeleted deleted_by returns data value
template = Onetime::Mail::Templates::OrganizationDeleted.new(@valid_data)
template.deleted_by
#=> 'owner@example.com'

## OrganizationDeleted deleted_at returns provided value when given
data = @valid_data.merge(deleted_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::OrganizationDeleted.new(data)
template.deleted_at
#=> '2024-01-15T10:30:00Z'

## OrganizationDeleted deleted_at_formatted returns human-readable date
data = @valid_data.merge(deleted_at: '2024-01-15T10:30:00Z')
template = Onetime::Mail::Templates::OrganizationDeleted.new(data)
template.deleted_at_formatted
#=> 'January 15, 2024 at 10:30 UTC'

## OrganizationDeleted support_path returns expected path
template = Onetime::Mail::Templates::OrganizationDeleted.new(@valid_data)
template.support_path
#=> '/support'

## OrganizationDeleted baseuri respects data override
data = @valid_data.merge(baseuri: 'https://custom.example.com')
template = Onetime::Mail::Templates::OrganizationDeleted.new(data)
template.baseuri
#=> 'https://custom.example.com'

## OrganizationDeleted subject returns a non-empty string
template = Onetime::Mail::Templates::OrganizationDeleted.new(@valid_data)
template.subject.is_a?(String) && !template.subject.empty?
#=> true
