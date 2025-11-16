# try/cli/domains_command_try.rb
#
# frozen_string_literal: true

require 'spec/spec_helper.rb'

# CLI Domains Command Tests
#
# Tests for the enhanced domains CLI command including:
# - Listing domains with organization info
# - Filtering (orphaned, verified, by org)
# - Domain info display
# - Transfer between organizations
# - Repair functionality
# - Bulk repair
#
# Setup test data and helper methods

@test_customer_1 = nil
@test_customer_2 = nil
@test_org_1 = nil
@test_org_2 = nil
@test_domain_1 = nil
@test_domain_2 = nil
@orphaned_domain = nil

def cleanup_test_data
  [@test_domain_1, @test_domain_2, @orphaned_domain].compact.each do |domain|
    domain.destroy! rescue nil
  end
  [@test_org_1, @test_org_2].compact.each do |org|
    org.destroy! rescue nil
  end
  [@test_customer_1, @test_customer_2].compact.each do |cust|
    cust.destroy! rescue nil
  end
end

def create_test_organizations
  # Create test customers first
  timestamp = Familia.now.to_i
  @test_customer_1 = Onetime::Customer.create!(email: "testcust1_#{timestamp}@example.com")
  @test_customer_2 = Onetime::Customer.create!(email: "testcust2_#{timestamp}@example.com")

  # Create test organizations
  @test_org_1 = Onetime::Organization.create!(
    "Test Org 1",
    @test_customer_1,
    "billing@testorg1.com"
  )

  @test_org_2 = Onetime::Organization.create!(
    "Test Org 2",
    @test_customer_2,
    "billing@testorg2.com"
  )
end

def create_test_domains
  # Domain with org_id (owned)
  @test_domain_1 = Onetime::CustomDomain.create!("testdomain1.example.com", @test_org_1.objid)
  @test_domain_1.verified = 'true'
  @test_domain_1.save

  # Domain with org_id (unverified)
  @test_domain_2 = Onetime::CustomDomain.create!("testdomain2.example.com", @test_org_2.objid)
  @test_domain_2.verified = 'false'
  @test_domain_2.save

  # Orphaned domain (no org_id)
  @orphaned_domain = Onetime::CustomDomain.parse("orphaned.example.com", nil)
  @orphaned_domain.save
end

## Setup: Create test data
# Ensure clean Redis state for testing
if ENV['ENV'] == 'test'
  Familia.dbclient.flushdb
  OT.info "Cleaned Redis for CLI domain command tests"
end

cleanup_test_data
create_test_organizations
create_test_domains

## Test DomainsCommand class exists
Onetime::DomainsCommand
#=> Onetime::DomainsCommand

## Test DomainsCommand inherits from CLI
Onetime::DomainsCommand.superclass
#=> Onetime::CLI

## Test load_domain_by_name helper
cmd = Onetime::DomainsCommand.new
domain = cmd.send(:load_domain_by_name, "testdomain1.example.com")
domain.display_domain
#=> "testdomain1.example.com"

## Test load_domain_by_name with non-existent domain
cmd = Onetime::DomainsCommand.new
domain = cmd.send(:load_domain_by_name, "nonexistent.example.com")
domain
#=> nil

## Test load_organization helper
cmd = Onetime::DomainsCommand.new
org = cmd.send(:load_organization, @test_org_1.org_id)
org.org_id
#=> @test_org_1.org_id

## Test get_organization_info for owned domain
cmd = Onetime::DomainsCommand.new
info = cmd.send(:get_organization_info, @test_domain_1)
info.include?("Test Org 1")
#=> true

## Test get_organization_info for orphaned domain
cmd = Onetime::DomainsCommand.new
info = cmd.send(:get_organization_info, @orphaned_domain)
info
#=> "ORPHANED"

## Test format_domain_row
cmd = Onetime::DomainsCommand.new
row = cmd.send(:format_domain_row, @test_domain_1)
row.include?("testdomain1.example.com")
#=> true

## Test format_domain_row includes verification status
cmd = Onetime::DomainsCommand.new
row = cmd.send(:format_domain_row, @test_domain_1)
row.include?("yes")
#=> true

## Test apply_filters with no filters
cmd = Onetime::DomainsCommand.new
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.size
#=> 3

## Test apply_filters with orphaned filter
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(orphaned: true))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.size
#=> 1

## Test apply_filters orphaned filter returns only orphaned
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(orphaned: true))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.first.display_domain
#=> "orphaned.example.com"

## Test apply_filters with org_id filter
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(org_id: @test_org_1.org_id))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.size
#=> 1

## Test apply_filters org_id filter returns correct domain
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(org_id: @test_org_1.org_id))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.first.display_domain
#=> "testdomain1.example.com"

## Test apply_filters with verified filter
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(verified: true))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.size
#=> 1

## Test apply_filters verified filter returns verified domain
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(verified: true))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.first.verified
#=> "true"

## Test apply_filters with unverified filter
cmd = Onetime::DomainsCommand.new
cmd.instance_variable_set(:@option, OpenStruct.new(unverified: true))
domains = [@test_domain_1, @test_domain_2, @orphaned_domain]
filtered = cmd.send(:apply_filters, domains)
filtered.size >= 1
#=> true

## Test format_timestamp with valid timestamp
cmd = Onetime::DomainsCommand.new
timestamp = Time.now.to_i
formatted = cmd.send(:format_timestamp, timestamp)
formatted.include?("UTC")
#=> true

## Test format_timestamp with nil
cmd = Onetime::DomainsCommand.new
formatted = cmd.send(:format_timestamp, nil)
formatted
#=> "N/A"

## Test format_timestamp with invalid timestamp
cmd = Onetime::DomainsCommand.new
formatted = cmd.send(:format_timestamp, "invalid")
formatted
#=> "invalid"

## Test domain can be transferred between organizations
original_org_id = @test_domain_2.org_id
@test_org_1.add_domain(@test_domain_2.domainid)
@test_domain_2.org_id = @test_org_1.org_id
@test_domain_2.save
@test_org_2.remove_domain(@test_domain_2.domainid)
reloaded = Onetime::CustomDomain.load_by_display_domain("testdomain2.example.com")
reloaded.org_id
#=> @test_org_1.org_id

## Test transferred domain is in new org's collection
@test_org_1.list_domains.include?(@test_domain_2.domainid)
#=> true

## Test transferred domain is not in old org's collection
@test_org_2.list_domains.include?(@test_domain_2.domainid)
#=> false

## Test orphaned domain can be assigned to organization
@orphaned_domain.org_id = @test_org_1.org_id
@orphaned_domain.save
@test_org_1.add_domain(@orphaned_domain.domainid)
reloaded = Onetime::CustomDomain.load_by_display_domain("orphaned.example.com")
reloaded.org_id
#=> @test_org_1.org_id

## Test assigned orphaned domain is in org's collection
@test_org_1.list_domains.include?(@orphaned_domain.domainid)
#=> true

## Test domain repair scenario: domain has org_id but not in collection
test_domain_3 = Onetime::CustomDomain.parse("testdomain3.example.com", @test_org_2.org_id)
test_domain_3.save
domains_before = @test_org_2.list_domains
domains_before.include?(test_domain_3.domainid)
#=> false

## Test repair: add to collection
@test_org_2.add_domain(test_domain_3.domainid)
domains_after = @test_org_2.list_domains
domains_after.include?(test_domain_3.domainid)
#=> true

## Teardown: Clean up test data
cleanup_test_data
test_domain_3.destroy! rescue nil
