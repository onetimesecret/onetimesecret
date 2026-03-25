# try/unit/models/v2/customer_try.rb
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
#=~> /[0-9a-z]{16,}/

## New instance of customer has a dbkey
@cust.dbkey
#=> "customer:#{@objid}:object"

## Customer.dummy is frozen (used for timing-safe comparisons)
@dummy = Onetime::Customer.dummy
@dummy.frozen?
#=> true

## Customer.dummy has role='anon' (for timing attacks prevention)
@dummy.role
#=> 'anon'

## anonymous? returns true when role is 'anonymous'
anon_cust = Onetime::Customer.new(role: 'anonymous')
anon_cust.anonymous?
#=> true

## anonymous? returns false when role is 'customer' (even if custid='anon')
# NOTE: custid='anon' no longer makes a customer anonymous - only role matters
regular_cust = Onetime::Customer.new(role: 'customer', custid: 'anon')
regular_cust.anonymous?
#=> false

## Trying to save anonymous customer raises Onetime::Problem
anon_cust = Onetime::Customer.new(role: 'anonymous')
anon_cust.save
#=!> Onetime::Problem

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


# ==========================================================================
# Hash-like accessor [] tests (security boundary) [Task #103]
#
# These tests verify the allowlist-based [] accessor that replaced the
# open-ended send() method. Only HASH_ACCESSIBLE_FIELDS can be accessed.
# ==========================================================================

## Hash accessor: allowlisted fields work via [] accessor
# Tests that :role, :email, :custid, :objid, :planid, :locale all return values
cust = Onetime::Customer.new(email: generate_random_email)
cust.role = 'customer'
cust.planid = 'basic'
cust.locale = 'en'
cust.save
results = {
  role: cust[:role],
  roles: cust[:roles],  # :roles is aliased to :role for Otto compatibility
  planid: cust[:planid],
  locale: cust[:locale],
}
cust.delete!
results
#=> { role: 'customer', roles: 'customer', planid: 'basic', locale: 'en' }

## Hash accessor: [:email] returns the email (allowlisted)
email_for_test = generate_random_email
cust = Onetime::Customer.new(email: email_for_test)
cust.save
result = cust[:email]
cust.delete!
result == email_for_test
#=> true

## Hash accessor: [:custid] returns a valid UUID (allowlisted)
cust = Onetime::Customer.new(email: generate_random_email)
cust.save
result = cust[:custid]
cust.delete!
result
#=~> /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

## Hash accessor: [:objid] returns a valid UUID (allowlisted)
cust = Onetime::Customer.new(email: generate_random_email)
cust.save
result = cust[:objid]
cust.delete!
result
#=~> /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

## Hash accessor: string key 'role' is coerced to symbol
cust = Onetime::Customer.new(email: generate_random_email)
cust.role = 'admin'
cust.save
result = cust['role']
cust.delete!
result
#=> 'admin'

## Hash accessor: non-allowlisted fields return nil (security boundary)
# Tests that dangerous fields like :passphrase, :apitoken, :destroy! return nil
cust = Onetime::Customer.new(email: generate_random_email)
cust.save
results = {
  passphrase: cust[:passphrase],
  password: cust[:password],
  apitoken: cust[:apitoken],
  destroy_bang: cust[:destroy!],
  delete_bang: cust[:delete!],
  system: cust[:system],
  private_key: cust[:private_key],
}
cust.delete!
results
#=> { passphrase: nil, password: nil, apitoken: nil, destroy_bang: nil, delete_bang: nil, system: nil, private_key: nil }

## HASH_ACCESSIBLE_FIELDS constant is frozen
Onetime::Customer::HASH_ACCESSIBLE_FIELDS.frozen?
#=> true

## HASH_ACCESSIBLE_FIELDS contains exactly the expected fields
Onetime::Customer::HASH_ACCESSIBLE_FIELDS.sort
#=> [:created, :custid, :email, :locale, :objid, :planid, :role, :roles, :user_id]
