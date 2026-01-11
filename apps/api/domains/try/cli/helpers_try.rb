# apps/api/domains/try/cli/helpers_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'

OT.boot! :test
require_relative '../../cli/helpers'

# Tests for DomainsHelpers module
#
# Helper methods shared across domain CLI commands:
# - apply_filters: Filter domain lists by various criteria
# - format_domain_row: Format domain info for display
# - get_organization_info: Get org info string for a domain
# - load_domain_by_name: Load domain by display name
# - load_organization: Load organization by ID
# - format_timestamp: Format Unix timestamp for display

# Test helper class that includes the module
class TestDomainsHelper
  include Onetime::CLI::DomainsHelpers
end

@test_customer_1 = nil
@test_customer_2 = nil
@test_org_1 = nil
@test_org_2 = nil
@test_domain_1 = nil
@test_domain_2 = nil
@helper = nil

def cleanup_test_data
  [@test_domain_1, @test_domain_2].compact.each do |domain|
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
  @test_id = SecureRandom.hex(4)
  @test_customer_1 = Onetime::Customer.create!(email: "testcust1_#{@test_id}@example.com")
  @test_customer_2 = Onetime::Customer.create!(email: "testcust2_#{@test_id}@example.com")

  @test_org_1 = Onetime::Organization.create!(
    "Test Org 1 #{@test_id}",
    @test_customer_1,
    "billing+helpers1+#{@test_id}@onetimesecret.com"
  )

  @test_org_2 = Onetime::Organization.create!(
    "Test Org 2 #{@test_id}",
    @test_customer_2,
    "billing+helpers2+#{@test_id}@onetimesecret.com"
  )
end

def create_test_domains
  @test_domain_1 = Onetime::CustomDomain.create!("testdomain1-#{@test_id}.example.com", @test_org_1.objid)
  @test_domain_1.verified = 'true'
  @test_domain_1.save

  @test_domain_2 = Onetime::CustomDomain.create!("testdomain2-#{@test_id}.example.com", @test_org_2.objid)
  @test_domain_2.verified = 'false'
  @test_domain_2.save
end

## Setup
if ENV['ENV'] == 'test'
  Familia.dbclient.flushdb
  OT.info "Cleaned Redis for domains helpers tests"
end

cleanup_test_data
create_test_organizations
create_test_domains
@helper = TestDomainsHelper.new

## Test CustomDomain.parse requires org_id
Onetime::CustomDomain.parse("test.example.com", nil)
#=!> Onetime::Problem

## Test load_domain_by_name returns domain
domain = @helper.load_domain_by_name(@test_domain_1.display_domain)
domain.display_domain
#=> @test_domain_1.display_domain

## Test load_domain_by_name with non-existent domain returns nil
domain = @helper.load_domain_by_name("nonexistent.example.com")
domain
#=> nil

## Test load_organization returns org
org = @helper.load_organization(@test_org_1.org_id)
org.org_id
#=> @test_org_1.org_id

## Test get_organization_info for owned domain
info = @helper.get_organization_info(@test_domain_1)
info.include?("Test Org 1")
#=> true

## Test format_domain_row includes domain name
row = @helper.format_domain_row(@test_domain_1)
row.include?(@test_domain_1.display_domain)
#=> true

## Test format_domain_row includes verification status
row = @helper.format_domain_row(@test_domain_1)
row.include?("yes")
#=> true

## Test apply_filters with no filters returns all
domains = [@test_domain_1, @test_domain_2]
filtered = @helper.apply_filters(domains)
filtered.size
#=> 2

## Test apply_filters with org_id filter
domains = [@test_domain_1, @test_domain_2]
filtered = @helper.apply_filters(domains, org_id: @test_org_1.org_id)
filtered.size
#=> 1

## Test apply_filters org_id filter returns correct domain
domains = [@test_domain_1, @test_domain_2]
filtered = @helper.apply_filters(domains, org_id: @test_org_1.org_id)
filtered.first.display_domain
#=> @test_domain_1.display_domain

## Test apply_filters with verified filter
domains = [@test_domain_1, @test_domain_2]
filtered = @helper.apply_filters(domains, verified: true)
filtered.size
#=> 1

## Test apply_filters verified filter returns verified domain
domains = [@test_domain_1, @test_domain_2]
filtered = @helper.apply_filters(domains, verified: true)
filtered.first.verified
#=> "true"

## Test apply_filters with unverified filter
domains = [@test_domain_1, @test_domain_2]
filtered = @helper.apply_filters(domains, unverified: true)
filtered.size >= 1
#=> true

## Test format_timestamp with valid timestamp
timestamp = Time.now.to_i
formatted = @helper.format_timestamp(timestamp)
formatted.include?("UTC")
#=> true

## Test format_timestamp with nil returns N/A
formatted = @helper.format_timestamp(nil)
formatted
#=> "N/A"

## Test format_timestamp with string converts to epoch
formatted = @helper.format_timestamp("invalid")
formatted.include?("1969") || formatted.include?("1970")
#=> true

## Teardown
cleanup_test_data
