require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

## Clean up
Familia.dbclient(6).flushdb if ENV['ENV'] == 'test'

# Create fixtures
@timestamp = Familia.now.to_i
@cust = Onetime::Customer.create!("isolated_#{@timestamp}@test.com")
@org = Onetime::Organization.new(
  display_name: "Isolated Org",
  owner_id: @cust.custid,
  contact_email: "isolated_#{@timestamp}@org.com"
)
@org.save

## Before add - forward relationship empty
@org.members.size
#=> 0

## Before add - reverse relationship empty
@cust.organization_instances.size
#=> 0

## Perform bidirectional add using auto-generated method
@org.add_members_instance(@cust)
nil
#=> nil

## After add - forward relationship populated
@org.members.size
#=> 1

## After add - org.members contains customer.objid
@org.members.member?(@cust.objid)
#=> true

## Check what methods are available on org
puts @org.methods.grep(/member/).sort.inspect
nil
#=> nil

## Check what organization methods are available on customer
puts @cust.methods.grep(/organization/).sort.inspect
nil
#=> nil

## Check participations data after add
puts "Participations: #{@cust.participations.members.inspect}"
nil
#=> nil

## Check Organization.config_name
puts "Organization.config_name: #{Onetime::Organization.config_name.inspect}"
nil
#=> nil

## Check participating_ids_for_target
ids = @cust.participating_ids_for_target(Onetime::Organization)
puts "Participating IDs: #{ids.inspect}"
nil
#=> nil

## After add - reverse relationship populated
@cust.organization_instances.size
#=> 1

## After add - customer can see org
@cust.organization_instances.first.orgid
#=> @org.orgid
