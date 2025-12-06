# apps/api/domains/try/cli/repair_command_try.rb
#
# frozen_string_literal: true

require 'spec/spec_helper.rb'

# Note: These tests verify domain repair model behavior.
# The DomainsRepairCommand CLI is tested via integration tests.

# Tests for DomainsRepairCommand
#
# Repair domain-organization relationship inconsistencies

@test_customer_1 = nil
@test_customer_2 = nil
@test_org_1 = nil
@test_org_2 = nil
@test_domain_3 = nil

def cleanup_test_data
  [@test_domain_3].compact.each do |domain|
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
  timestamp = Familia.now.to_i
  @test_customer_1 = Onetime::Customer.create!(email: "testcust1_#{timestamp}@example.com")
  @test_customer_2 = Onetime::Customer.create!(email: "testcust2_#{timestamp}@example.com")

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

## Setup
if ENV['ENV'] == 'test'
  Familia.dbclient.flushdb
  OT.info "Cleaned Redis for domains repair tests"
end

cleanup_test_data
create_test_organizations

## Test domain repair scenario: domain has org_id but not in collection
@test_domain_3 = Onetime::CustomDomain.parse("testdomain3.example.com", @test_org_2.org_id)
@test_domain_3.save
domains_before = @test_org_2.list_domains
domains_before.map(&:domainid).include?(@test_domain_3.domainid)
#=> false

## Test repair: add to collection
@test_org_2.add_domain(@test_domain_3)
domains_after = @test_org_2.list_domains
domains_after.map(&:domainid).include?(@test_domain_3.domainid)
#=> true

## Teardown
cleanup_test_data
@test_domain_3.destroy! rescue nil
