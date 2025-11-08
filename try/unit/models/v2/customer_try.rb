# try/25_customer_try.rb
#
# frozen_string_literal: true

# These tryouts test the customer model functionality in the Onetime application.
# They cover various aspects of customer management, including:
#
# 1. Customer creation and initialization
# 2. Customer attributes (planid, custid, role, etc.)
# 3. Customer states (pending, verified, active)
# 4. Timestamp handling (created, updated, last_login)
# 5. Customer destruction process
#
# These tests aim to verify the correct behavior of the Onetime::Customer class,
# which is essential for managing user accounts in the application.
#
# The tryouts simulate different customer scenarios and test the Onetime::Customer class's
# behavior without needing to run the full application, allowing for targeted testing
# of these specific scenarios.

#ENV['FAMILIA_TRACE'] = '1'
require_relative '../../../support/test_helpers'
#Familia.debug = true

# Load the app
OT.boot! :test, false

# Setup some variables for these tryouts
@now = Time.now.strftime("%Y%m%d%H%M%S")
@email_address = generate_random_email
@find_by_email_address = generate_random_email
@cust = Onetime::Customer.new email: @email_address
@objid = @cust.objid

# TRYOUTS

## New instance of customer has no planid (not saved yet)
@cust.planid
#=> nil

## New instance of customer has a custid
@cust.custid
#=~> /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

## New instance of customer has an objid
@cust.objid
#=~> /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

## New instance of customer has an extid
@cust.extid
#=~> /ext_[0-9a-z]{16}/

## New instance of customer has a dbkey
@cust.dbkey
#=> "customer:#{@objid}:object"

## Can "create" an anonymous user (more like simulate)
@anonymous = Onetime::Customer.anonymous
@anonymous.role
#=> 'customer'

## Anonymous is a Customer class
@anonymous.class
#=> Onetime::Customer

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
@anonymous.save
#=!> Onetime::Problem
#=!> "Anonymous cannot be saved Onetime::Customer customer:#{@objid}:object"

## Object name and dbkey are no longer equivalent.
## This is a reference back to Familia v0.10.2 era which
## used to have a name method that returned the key.
@cust.respond_to?(:name) ||
(@cust.respond_to?(:name) && @cust.name.eql?(@cust.dbkey))
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
ttl = @cust.default_expiration
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

## Customer.instances has the correct dbkey
Onetime::Customer.instances.dbkey
#=> "customer:instances"

## Customer.domains has the correct dbkey
Onetime::Customer.domains.dbkey
#=> "customer:domains"

## Customer.instances is a Familia::SortedSet
Onetime::Customer.instances.class
#=> Familia::SortedSet

## Customer.domains is a Familia::HashKey
Onetime::Customer.domains.class
#=> Familia::HashKey

## Customer find by email, nil by default
email = "test1+#{rand(10000000)}@example.com"
Onetime::Customer.find_by_email(email)
#=> nil

## Customer find by email, when the record exists
cust = Onetime::Customer.create!(@find_by_email_address)
Onetime::Customer.find_by_email(@find_by_email_address)
#=:> Onetime::Customer


test_cust = Onetime::Customer.find_by_email(@find_by_email_address)
test_cust.delete!
