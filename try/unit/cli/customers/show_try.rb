# try/unit/cli/customers/show_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots customers show
#
# Command options:
#   identifier   Email address or extid (required)
#   --full       Show unobscured email address
#   --json       Output as JSON
#
# Run: bundle exec try try/unit/cli/customers/show_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :cli
require 'onetime/cli'

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create test fixtures
@cust = Onetime::Customer.create!(email: "cli_show_#{@test_suffix}@test.com")
@cust.role = 'customer'
@cust.planid = 'basic'
@cust.locale = 'en'
@cust.save

# Create an organization and add customer as member
@org_owner = Onetime::Customer.create!(email: "cli_org_owner_#{@test_suffix}@test.com")
@org = Onetime::Organization.create!("Test Organization", @org_owner, "billing_#{@test_suffix}@test.com")
@org.add_members_instance(@cust, through_attrs: { role: 'member' })

# -------------------------------------------------------------------
# Helper method to simulate CLI show command behavior
# This mirrors what the actual command does
# -------------------------------------------------------------------

def show_customer_cli(identifier:, full: false, json: false)
  # Normalize email for lookup via canonical method
  normalized = OT::Utils.normalize_email(identifier)

  if normalized.empty?
    return { success: false, error: 'Identifier is required' }
  end

  customer = Onetime::Customer.load_by_extid_or_email(normalized)

  unless customer
    return { success: false, error: "Customer not found: #{identifier}" }
  end

  orgs = customer.organization_instances.to_a.compact

  email_display = full ? customer.email : customer.obscure_email

  if json
    org_data = orgs.map do |org|
      {
        objid: org.objid,
        extid: org.extid,
        name: org.display_name,
      }
    end

    data = {
      extid: customer.extid,
      objid: customer.objid,
      custid: customer.custid,
      email: email_display,
      role: customer.role,
      planid: customer.planid,
      locale: customer.locale,
      verified: customer.verified?,
      created: customer.created.to_f,
      default_org_id: customer.default_org_id,
      organizations: org_data,
    }

    {
      success: true,
      customer: customer,
      output_format: :json,
      data: data
    }
  else
    {
      success: true,
      customer: customer,
      output_format: :text,
      email_display: email_display,
      organizations: orgs
    }
  end
end

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## CustomersShowCommand exists and inherits from Command
Onetime::CLI::CustomersShowCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## CustomersShowCommand is a Dry::CLI::Command
cmd = Onetime::CLI::CustomersShowCommand.new
cmd.is_a?(Dry::CLI::Command)
#=> true

# -------------------------------------------------------------------
# Happy Path: Lookup by email
# -------------------------------------------------------------------

## Lookup by email returns success
@result = show_customer_cli(identifier: @cust.email)
@result[:success]
#=> true

## Lookup by email finds correct customer
@result[:customer].objid == @cust.objid
#=> true

## Lookup by email shows obscured email by default
@result[:email_display].include?('*')
#=> true

## Lookup by email includes organization memberships
@result[:organizations].length > 0
#=> true

## Organization in result matches the one we added
@result[:organizations].first.objid == @org.objid
#=> true

# -------------------------------------------------------------------
# Happy Path: Lookup by extid
# -------------------------------------------------------------------

## Lookup by extid returns success
@extid_result = show_customer_cli(identifier: @cust.extid)
@extid_result[:success]
#=> true

## Lookup by extid finds correct customer
@extid_result[:customer].email == @cust.email
#=> true

# -------------------------------------------------------------------
# Happy Path: --full flag shows unobscured email
# -------------------------------------------------------------------

## Full flag shows complete email
@full_result = show_customer_cli(identifier: @cust.email, full: true)
@full_result[:email_display] == @cust.email
#=> true

## Full flag email does not contain asterisks
@full_result[:email_display].include?('*')
#=> false

# -------------------------------------------------------------------
# Happy Path: --json flag outputs structured data
# -------------------------------------------------------------------

## JSON flag returns json output format
@json_result = show_customer_cli(identifier: @cust.email, json: true)
@json_result[:output_format]
#=> :json

## JSON output includes customer extid
@json_result[:data][:extid] == @cust.extid
#=> true

## JSON output includes customer objid
@json_result[:data][:objid] == @cust.objid
#=> true

## JSON output includes custid
@json_result[:data][:custid] == @cust.custid
#=> true

## JSON output includes role
@json_result[:data][:role] == 'customer'
#=> true

## JSON output includes planid
@json_result[:data][:planid] == 'basic'
#=> true

## JSON output includes locale
@json_result[:data][:locale] == 'en'
#=> true

## JSON output includes verified status
@json_result[:data].key?(:verified)
#=> true

## JSON output includes created timestamp
@json_result[:data][:created].is_a?(Float)
#=> true

## JSON output includes default_org_id (nil by default)
@json_result[:data].key?(:default_org_id)
#=> true

## JSON output includes organizations array
@json_result[:data][:organizations].is_a?(Array)
#=> true

## JSON organizations include objid
@json_result[:data][:organizations].first[:objid] == @org.objid
#=> true

## JSON organizations include extid
@json_result[:data][:organizations].first[:extid] == @org.extid
#=> true

## JSON organizations include display_name as name
@json_result[:data][:organizations].first[:name] == "Test Organization"
#=> true

# -------------------------------------------------------------------
# Happy Path: --json with --full flag
# -------------------------------------------------------------------

## JSON with full flag shows complete email
@json_full = show_customer_cli(identifier: @cust.email, json: true, full: true)
@json_full[:data][:email] == @cust.email
#=> true

## JSON without full flag shows obscured email
@json_obscured = show_customer_cli(identifier: @cust.email, json: true, full: false)
@json_obscured[:data][:email].include?('*')
#=> true

# -------------------------------------------------------------------
# Happy Path: Customer with default_org_id set
# -------------------------------------------------------------------

## Set default_org_id and verify it shows in output
@cust.default_org_id = @org.objid
@cust.save
@default_result = show_customer_cli(identifier: @cust.email, json: true)
@default_result[:data][:default_org_id] == @org.objid
#=> true

## Clear default_org_id for remaining tests
@cust.default_org_id = nil
@cust.save
true
#=> true

# -------------------------------------------------------------------
# Error Cases: Customer not found (email)
# -------------------------------------------------------------------

## Non-existent email returns error
@not_found = show_customer_cli(identifier: "nonexistent_#{@test_suffix}@test.com")
@not_found[:success]
#=> false

## Error message mentions customer not found
@not_found[:error].include?('Customer not found')
#=> true

# -------------------------------------------------------------------
# Error Cases: Customer not found (extid)
# -------------------------------------------------------------------

## Non-existent extid returns error
@extid_not_found = show_customer_cli(identifier: "ur#{SecureRandom.hex(12)}")
@extid_not_found[:success]
#=> false

## Error message for extid not found
@extid_not_found[:error].include?('Customer not found')
#=> true

# -------------------------------------------------------------------
# Error Cases: Empty identifier
# -------------------------------------------------------------------

## Empty string returns error
@empty_result = show_customer_cli(identifier: '')
@empty_result[:success]
#=> false

## Empty identifier error message
@empty_result[:error]
#=> 'Identifier is required'

## Whitespace-only string returns error
@whitespace_result = show_customer_cli(identifier: '   ')
@whitespace_result[:success]
#=> false

# -------------------------------------------------------------------
# Edge Cases: Case-insensitive email lookup
# -------------------------------------------------------------------

## Uppercase email finds customer
@upper_result = show_customer_cli(identifier: @cust.email.upcase)
@upper_result[:success]
#=> true

## Uppercase lookup finds correct customer
@upper_result[:customer].objid == @cust.objid
#=> true

# -------------------------------------------------------------------
# Edge Cases: Email with leading/trailing whitespace
# -------------------------------------------------------------------

## Email with leading whitespace is trimmed
@leading_ws = show_customer_cli(identifier: "  #{@cust.email}")
@leading_ws[:success]
#=> true

## Email with trailing whitespace is trimmed
@trailing_ws = show_customer_cli(identifier: "#{@cust.email}  ")
@trailing_ws[:success]
#=> true

# -------------------------------------------------------------------
# Edge Cases: Customer with no organizations
# -------------------------------------------------------------------

## Create customer with no org memberships
@no_org_cust = Onetime::Customer.create!(email: "cli_no_org_#{@test_suffix}@test.com")
@no_org_result = show_customer_cli(identifier: @no_org_cust.email)
@no_org_result[:success]
#=> true

## Customer with no orgs has empty organizations list
@no_org_result[:organizations].length
#=> 0

## JSON output for customer with no orgs
@no_org_json = show_customer_cli(identifier: @no_org_cust.email, json: true)
@no_org_json[:data][:organizations]
#=> []

# -------------------------------------------------------------------
# Edge Cases: Customer with multiple organizations
# -------------------------------------------------------------------

## Create second organization and add customer
@org2 = Onetime::Organization.create!("Second Org", @org_owner, "billing2_#{@test_suffix}@test.com")
@org2.add_members_instance(@cust, through_attrs: { role: 'admin' })
@multi_org_result = show_customer_cli(identifier: @cust.email)
@multi_org_result[:organizations].length >= 2
#=> true

## JSON output includes all organizations
@multi_org_json = show_customer_cli(identifier: @cust.email, json: true)
@multi_org_json[:data][:organizations].length >= 2
#=> true

# -------------------------------------------------------------------
# Cleanup
# -------------------------------------------------------------------

[@org, @org2, @cust, @org_owner, @no_org_cust].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
