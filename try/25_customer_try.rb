# frozen_string_literal: true

# These tryouts test the customer model functionality in the OneTime application.
# They cover various aspects of customer management, including:
#
# 1. Customer creation and initialization
# 2. Customer attributes (planid, custid, role, etc.)
# 3. Customer states (pending, verified, active)
# 4. Timestamp handling (created, updated, last_login)
# 5. Customer destruction process
#
# These tests aim to verify the correct behavior of the OT::Customer class,
# which is essential for managing user accounts in the application.
#
# The tryouts simulate different customer scenarios and test the OT::Customer class's
# behavior without needing to run the full application, allowing for targeted testing
# of these specific scenarios.


require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

# Setup some variables for these tryouts
@now = Time.now.strftime("%Y%m%d%H%M%S")
@model_class = OT::Customer
@email_address = "tryouts+#{@now}@onetimesecret.com"
@cust = OT::Customer.new @email_address

# TRYOUTS

## New instance of customer has no planid (not saved yet)
@cust.planid
#=> nil

## New instance of customer has a custid
@cust.custid
#=> @email_address

## New instance of customer has a rediskey
p [:email, @email_address]
@cust.rediskey
#=> "customer:#{@email_address}:object"

## Object name and rediskey are equivalent
@cust.rediskey.eql?(@cust.name)
#=> true

## New un-saved instance of customer has a role of 'customer'
@cust.role
#=> 'customer'

## New un-saved instance of customer is pending
@cust.pending?
#=> true

## New un-saved instance of customer is not verified
@cust.verified?
#=> false

## Customers don't have a default ttl
ttl = @cust.ttl
[ttl.class, ttl]
#=> [NilClass, nil]

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
