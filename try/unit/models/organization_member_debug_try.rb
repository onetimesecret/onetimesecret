require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

## Clean up any existing test data from previous runs
# Note: Using dbclient(6) for test database
Familia.dbclient(6).flushdb if ENV['ENV'] == 'test'

# Use unique email to avoid conflicts
@timestamp = Familia.now.to_i
@email = "debug_#{@timestamp}@test.com"

## Create customer
@customer = Onetime::Customer.create!(@email)
@customer.email
#=> @email

## Customer has add_to_organization_members method
@customer.respond_to?(:add_to_organization_members)
#=> true

## Create organization
@org_email = "debug-org_#{@timestamp}@test.com"
@org = Onetime::Organization.create!("Debug Org", @customer, @org_email)
@org.display_name
#=> "Debug Org"

## Check if customer was added to org.members
@org.members.size
#=> 1

## Check if customer.objid is in org.members
@org.members.member?(@customer.objid)
#=> true

## Check if org has add_members_instance method
@org.respond_to?(:add_members_instance)
#=> true

## Check reverse relationship
@customer.organization_instances.size
#=> 1

## Customer should see the org
@customer.organization_instances.first.orgid
#=> @org.orgid
