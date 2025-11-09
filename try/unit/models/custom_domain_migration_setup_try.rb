# Minimal test - just create customers and orgs, no domains

require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

# Ensure clean state
Familia.dbclient(6).flushdb if ENV['ENV'] == 'test'

# Create test data
@test_id = SecureRandom.hex(4)
@cust1 = Onetime::Customer.create!(email: "cust1_#{@test_id}@test.com")
@org1 = Onetime::Organization.create!("Org 1", @cust1, "org1_#{@test_id}@test.com")

@cust2 = Onetime::Customer.create!(email: "cust2_#{@test_id}@test.com")
# cust2 has no organization - edge case

## Customer 1 has organization ids (after reload)
@cust1_reloaded = Onetime::Customer.load(@cust1.objid)
@cust1_reloaded.organization_ids.size
#=> 1

## Customer 2 has no organization
@cust2.organization_ids.size
#=> 0

## Organization 1 exists
@org1.nil?
#=> false

# Teardown
Familia.dbclient(6).flushdb if ENV['ENV'] == 'test'
