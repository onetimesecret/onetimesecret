# try/debug/familia_v2_bidirectional_try.rb
#
# Debug Familia v2 bidirectional relationships
#

require_relative '../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

@owner = Onetime::Customer.create!(email: "debug_owner_#{Familia.now.to_i}@test.com")
@org = Onetime::Organization.create!("Debug Org", @owner, "billing@debug.com")

## Organization was created
@org.class
#=> Onetime::Organization

## Owner was added as member (forward relationship)
@org.member?(@owner)
#=> true

## Check if owner has organization_instances method
@owner.respond_to?(:organization_instances)
#=> true

## Check owner organization_instances value
@owner.organization_instances.class
#=> Array

## Check owner organization_instances size
@owner.organization_instances.size
#=> 1

## Check first organization
@owner.organization_instances.first.class
#=> Onetime::Organization

# Teardown
@org.destroy!
@owner.destroy!
