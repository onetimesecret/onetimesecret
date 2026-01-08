# try/unit/models/v2/customer_colonel_tracking_try.rb
#
# frozen_string_literal: true

# Tests for Customer colonel tracking functionality using class_sorted_set.
#
# Covers:
# 1. Colonel role assignment adds customer to colonels sorted set
# 2. Colonel role removal removes customer from colonels sorted set
# 3. find_first_colonel returns correct customer when colonels exist
# 4. find_first_colonel returns nil when no colonels exist
# 5. Multiple colonel handling (first by score/timestamp)
# 6. Edge cases (role changes, customer destruction)
# 7. Sync functionality for catalog consistency

# Force simple auth mode - these tests only need Redis, not PostgreSQL
ENV['AUTHENTICATION_MODE'] = 'simple'

require_relative '../../../support/test_helpers'

OT.boot! :test, false

# Setup: create unique test emails for these tryouts
@email1 = generate_random_email
@email2 = generate_random_email
@email3 = generate_random_email

# Clear any existing colonels to start with clean state
Onetime::Customer.colonels.clear

# TRYOUTS

## Customer.colonels is a Familia::SortedSet
Onetime::Customer.colonels.class.to_s
#=> 'Familia::SortedSet'

## New customer has default role of 'customer'
@cust1 = Onetime::Customer.new(email: @email1)
@cust1.role
#=> 'customer'

## Saving customer with 'customer' role does not add to colonels set
@cust1.save
Onetime::Customer.colonels.member?(@cust1.identifier)
#=> false

## Changing role to colonel and saving adds to colonels set
@cust1.role = 'colonel'
@cust1.save
Onetime::Customer.colonels.member?(@cust1.identifier)
#=> true

## Colonels set has score (timestamp) for the colonel
score = Onetime::Customer.colonels.score(@cust1.identifier)
score.to_i > 0
#=> true

## find_first_colonel returns the colonel customer
first = Onetime::Customer.find_first_colonel
first.class
#=> Onetime::Customer

## find_first_colonel returns customer with correct identifier
first = Onetime::Customer.find_first_colonel
first.identifier == @cust1.identifier
#=> true

## find_first_colonel returns customer with colonel role
Onetime::Customer.find_first_colonel.role
#=> 'colonel'

## colonel_count returns correct count
Onetime::Customer.colonel_count
#=> 1

## list_colonels returns array of colonel customers
colonels = Onetime::Customer.list_colonels
colonels.is_a?(Array) && colonels.first.is_a?(Onetime::Customer)
#=> true

## Adding a second colonel updates the count
@cust2 = Onetime::Customer.new(email: @email2)
@cust2.role = 'colonel'
@cust2.save
Onetime::Customer.colonel_count
#=> 2

## Multiple colonels: find_first_colonel returns first by score (earliest)
# cust1 was added first, so should have lower score
first = Onetime::Customer.find_first_colonel
first.identifier == @cust1.identifier
#=> true

## Demoting from colonel removes from colonels set
@cust2.role = 'customer'
@cust2.save
Onetime::Customer.colonels.member?(@cust2.identifier)
#=> false

## Colonel count decreases after demotion
Onetime::Customer.colonel_count
#=> 1

## Re-promoting to colonel adds back to set with new timestamp
old_score = Onetime::Customer.colonels.score(@cust1.identifier)
sleep 0.1  # Ensure timestamp difference
@cust2.role = 'colonel'
@cust2.save
new_score = Onetime::Customer.colonels.score(@cust2.identifier)
new_score > old_score
#=> true

## Destroying a colonel customer removes from colonels set
cust2_id = @cust2.identifier
@cust2.destroy!
Onetime::Customer.colonels.member?(cust2_id)
#=> false

## find_first_colonel returns nil when no colonels exist
@cust1.role = 'customer'
@cust1.save
Onetime::Customer.colonels.clear  # Ensure clean state
Onetime::Customer.find_first_colonel
#=> nil

## colonel_count returns 0 when no colonels
Onetime::Customer.colonel_count
#=> 0

## list_colonels returns empty array when no colonels
Onetime::Customer.list_colonels
#=> []

## sync_colonel_catalog with dry_run reports what would be done
# First, manually add cust1 as colonel without using save
@cust1.role = 'colonel'
@cust1.instance_variable_set(:@previous_role, nil)  # Skip tracking
Onetime::Customer.colonels.clear  # Clear catalog
# Force save without colonel tracking (simulate inconsistent state)
@cust1.dbclient.hset(@cust1.dbkey, 'role', 'colonel')
result = Onetime::Customer.sync_colonel_catalog(dry_run: true)
result[:added] >= 1
#=> true

## sync_colonel_catalog actually syncs when dry_run is false
result = Onetime::Customer.sync_colonel_catalog(dry_run: false)
Onetime::Customer.colonels.member?(@cust1.identifier)
#=> true

# TEARDOWN

# Clean up test customers
[@cust1].each do |cust|
  begin
    cust.delete! if cust&.exists?
  rescue StandardError
    nil
  end
end

# Clear colonels catalog
Onetime::Customer.colonels.clear
