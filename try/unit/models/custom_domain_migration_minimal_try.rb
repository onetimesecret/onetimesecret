# Minimal test to debug the setup issue

require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

begin
  # Ensure clean state
  Familia.dbclient(6).flushdb if ENV['ENV'] == 'test'

  puts "Creating customer..."
  @test_id = SecureRandom.hex(4)
  @cust = Onetime::Customer.create!(email: "test_#{@test_id}@test.com")
  puts "Customer created with custid: #{@cust.custid}"

  puts "Creating organization..."
  @org = Onetime::Organization.create!("Test Org #{@test_id}", @cust, "billing_#{@test_id}@test.com")
  puts "Organization created with orgid: #{@org.orgid}"

  puts "Creating custom domain..."
  @domain_name = "test#{@test_id}.example.com"
  @domain = Onetime::CustomDomain.create!(@domain_name, @org.orgid)
  puts "Domain created: #{@domain.display_domain}"
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Setup requires Redis connection (#{e.class})"
  exit 0
end

## Customer exists
@cust.nil?
#=> false

## Customer has custid
@cust.custid.nil?
#=> false

## Organization exists
@org.nil?
#=> false

## Domain exists
@domain.nil?
#=> false

# Teardown
begin
  Familia.dbclient(6).flushdb if ENV['ENV'] == 'test'
rescue Redis::CannotConnectError, Redis::ConnectionError
  # Skip cleanup if Redis unavailable
end
