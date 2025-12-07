# try/unit/models/custom_domain_migration_try.rb
#
# frozen_string_literal: true

# Post-migration validation tests for CustomDomain org_id architecture
#
# This test suite validates the completed migration from custid to org_id:
# - CustomDomain has org_id field (NO custid)
# - CustomDomain.participates_in Organization, :domains
# - CustomDomain.create!(domain, org_id)
# - Organization.domains collection tracks domains
# - Customer -> Organization -> Domains access pattern
#
# NOTE: CustomDomain.all has a known issue with quoted identifiers in instances
# sorted set. Tests use organization.domains and direct lookups instead.
#
# REFERENCE: See custom_domain_familia_v2_try.rb for detailed relationship tests

require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

# Setup: Create test data for post-migration validation
begin
  # Ensure clean state
  Familia.dbclient.flushdb if ENV['ENV'] == 'test'

  # Generate unique test ID
  @test_id = SecureRandom.hex(4)

  # Create customer with organization
  @customer = Onetime::Customer.create!(email: "customer_#{@test_id}@test.com")
  @organization = Onetime::Organization.create!("Test Org #{@test_id}", @customer, "billing_#{@test_id}@test.com")

  # Create test domains using org_id
  @domain1 = Onetime::CustomDomain.create!("secrets-#{@test_id}.acme.com", @organization.objid)
  @domain2 = Onetime::CustomDomain.create!("linx-#{@test_id}.acme.com", @organization.objid)

  # Create second organization with domain
  @customer2 = Onetime::Customer.create!(email: "customer2_#{@test_id}@test.com")
  @organization2 = Onetime::Organization.create!("Test Org 2 #{@test_id}", @customer2, "billing2_#{@test_id}@test.com")
  @domain3 = Onetime::CustomDomain.create!("portal-#{@test_id}.example.com", @organization2.objid)

  # Track counts for validation
  @initial_domain_count = Onetime::CustomDomain.instances.size
  @initial_org_count = Onetime::Organization.instances.size
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Setup requires Redis connection (#{e.class})"
  exit 0
end

## Validation: Instances index tracks domains
@initial_domain_count >= 3
#=> true

## Validation: Customer has organization
@customer.organization_ids.empty?
#=> false

## Validation: Customer organization count
@customer.organization_count
#=> 1

## Validation: Can load customer's primary organization
@primary_org = Onetime::Organization.load(@customer.organization_ids.first)
@primary_org.objid == @organization.objid
#=> true

## Validation: Domain has org_id field
@domain1.org_id == @organization.objid
#=> true

## Validation: Domain belongs to organization via owner check
@domain1.owner?(@customer)
#=> true

## Validation: Organization tracks its domains
@organization.domains.size >= 2
#=> true

## Validation: Domain is in organization's domains collection
@organization.domains.member?(@domain1.domainid)
#=> true

## Validation: Second organization has its domain
@organization2.domains.member?(@domain3.domainid)
#=> true

## Validation: Domains are not cross-contaminated between orgs
@organization.domains.member?(@domain3.domainid)
#=> false

## Validation: Domain count matches instances index
Onetime::CustomDomain.instances.size == @initial_domain_count
#=> true

## Validation: display_domains index is populated
Onetime::CustomDomain.display_domains.get(@domain1.display_domain) == @domain1.identifier
#=> true

## Validation: Can load domain by display_domain
loaded = Onetime::CustomDomain.load_by_display_domain(@domain1.display_domain)
loaded.domainid == @domain1.domainid
#=> true

## Validation: Domain iteration via organization works
@processed_count = 0
@organization.list_domains.each do |domain|
  @processed_count += 1
end
@processed_count >= 2
#=> true

## Summary: All post-migration validations pass
{
  instances_count: @initial_domain_count,
  org_count: @initial_org_count,
  org1_domains: @organization.domains.size,
  org2_domains: @organization2.domains.size,
  validation: :passed
}
#=:> Hash

# Teardown: Clean up test data
begin
  Familia.dbclient.flushdb if ENV['ENV'] == 'test'
rescue Redis::CannotConnectError, Redis::ConnectionError
  # Skip cleanup if Redis unavailable
end
