# apps/api/v2/models/customer_try.rb

# These tryouts test the customer model functionality in the Onetime application.
# They cover various aspects of customer management, including:
#
# 1. Customer creation and initialization
# 2. Customer attributes (planid, custid, role, etc.)
# 3. Customer states (pending, verified, active)
# 4. Timestamp handling (created, updated, last_login)
# 5. Customer destruction process
#
# These tests aim to verify the correct behavior of the V2::Customer class,
# which is essential for managing user accounts in the application.
#
# The tryouts simulate different customer scenarios and test the V2::Customer class's
# behavior without needing to run the full application, allowing for targeted testing
# of these specific scenarios.

#ENV['FAMILIA_TRACE'] = '1'
require_relative '../../../../tests/helpers/test_models'
#Familia.debug = true

# Load the app
OT.boot! :test, false

# Setup some variables for these tryouts
@now = Time.now.strftime("%Y%m%d%H%M%S")
@email_address = "tryouts+#{@now}@onetimesecret.com"
@cust = V2::Customer.new @email_address

# TRYOUTS

## New instance of customer has no planid (not saved yet)
@cust.planid
#=> nil

## New instance of customer has a custid
p @cust.to_h
@cust.custid
#=> @email_address

## New instance of customer has a rediskey
p [:email, @email_address]
@cust.rediskey
#=> "customer:#{@email_address}:object"

## Can "create" an anonymous user (more like simulate)
@anonymous = V2::Customer.anonymous
@anonymous.custid
#=> 'anon'

## Anonymous is a Customer class
@anonymous.class
#=> V2::Customer

## Anonymous knows it's anonymous
@anonymous.anonymous?
#=> true

## Anonymous is frozen in time
@anonymous.frozen?
#=> true

## Anonymous doesn't exist
#@anonymous.destroy!
@anonymous.exists?
#=> false

## Trying to save anonymous raises hell on earth
begin
  @anonymous.save
rescue OT::Problem => e
  [e.class, e.message]
end
#=> [Onetime::Problem, "Anonymous cannot be saved V2::Customer customer:anon:object"]

## Object name and rediskey are no longer equivalent.
## This is a reference back to Familia v0.10.2 era which
## used to have a name method that returned the key.
@cust.respond_to?(:name) ||
(@cust.respond_to?(:name) && @cust.name.eql?(@cust.rediskey))
#=> false

## New un-saved instance of customer has a role of 'customer'
@cust.role
#=> 'customer'

## New un-saved instance of customer is pending
@cust.pending?
#=> true

## New un-saved instance of customer is not verified
@cust.verified?
#=> false

## Customers have a default ttl of 0
ttl = @cust.ttl
[ttl.class, ttl]
#=> [Integer, 0]

## New un-saved instance of customer is not active
@cust.active?
#=> false

## New un-saved instance of customer has a nil created timestamp
@cust.created
#=> nil

## New un-saved instance of customer has a nil updated timestamp
@cust.updated
#=> nil

## New un-saved instance of customer has a nil last_login timestamp
@cust.last_login
#=> nil

## New saved instance of customer has a created timestamp
@cust.save
@cust.created.nil?
#=> false

## New saved instance has a role of 'customer'
@cust.role
#=> 'customer'

## New saved instance has no specific locale
@cust.locale
#=> ''

## Destroyed customer is no longer active
@cust.destroy_requested!
@cust.active?
#=> false

## Destroyed customer is no longer pending
@cust.destroy_requested!
@cust.pending?
#=> false

## Destroyed customer is no longer verified
@cust.destroy_requested!
@cust.verified?
#=> false

## Customer.values has the correct rediskey
V2::Customer.values.rediskey
#=> "onetime:customer"

## Customer.domains has the correct rediskey
V2::Customer.domains.rediskey
#=> "onetime:customers:domain"

## Customer.values is a Familia::SortedSet
V2::Customer.values.class
#=> Familia::SortedSet

## Customer.domains is a Familia::HashKey
V2::Customer.domains.class
#=> Familia::HashKey
