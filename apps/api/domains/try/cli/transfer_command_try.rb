# apps/api/domains/try/cli/transfer_command_try.rb
#
# frozen_string_literal: true

require 'spec/spec_helper.rb'

# Note: These tests verify domain transfer model behavior.
# The DomainsTransferCommand CLI is tested via integration tests.

# Tests for DomainsTransferCommand
#
# Transfer domain between organizations

@test_customer_1 = nil
@test_customer_2 = nil
@test_org_1 = nil
@test_org_2 = nil
@test_domain_1 = nil
@test_domain_2 = nil

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

def create_test_domains
  @test_domain_1 = Onetime::CustomDomain.create!("testdomain1.example.com", @test_org_1.objid)
  @test_domain_1.verified = 'true'
  @test_domain_1.save

  @test_domain_2 = Onetime::CustomDomain.create!("testdomain2.example.com", @test_org_2.objid)
  @test_domain_2.verified = 'false'
  @test_domain_2.save
end

## Setup
if ENV['ENV'] == 'test'
  Familia.dbclient.flushdb
  OT.info "Cleaned Redis for domains transfer tests"
end

cleanup_test_data
create_test_organizations
create_test_domains

## Test domain can be transferred between organizations
original_org_id = @test_domain_2.org_id
@test_org_2.remove_domain(@test_domain_2)
@test_org_1.add_domain(@test_domain_2)
@test_domain_2.org_id = @test_org_1.org_id
@test_domain_2.save
reloaded = Onetime::CustomDomain.load_by_display_domain("testdomain2.example.com")
reloaded.org_id
#=> @test_org_1.org_id

## Test transferred domain is in new org's collection
@test_org_1.list_domains.map(&:domainid).include?(@test_domain_2.domainid)
#=> true

## Test transferred domain is not in old org's collection
@test_org_2.list_domains.map(&:domainid).include?(@test_domain_2.domainid)
#=> false

## Teardown
cleanup_test_data
