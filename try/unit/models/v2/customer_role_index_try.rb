# try/unit/models/v2/customer_role_index_try.rb
#
# frozen_string_literal: true

# Tests for Customer role indexing using Familia multi_index.
#
# Covers:
# 1. multi_index declaration provides find_all_by_role and role_index_for methods
# 2. Auto-indexing on save (new customers added to role-specific index)
# 3. Role changes update indexes correctly (removed from old, added to new)
# 4. Destroy removes customer from role index
# 5. find_all_by_role returns correct customers for any role
# 6. Backward-compatible methods: find_first_colonel, list_colonels, colonel_count
# 7. Chronological ordering by joined date

# Force simple auth mode - these tests only need Redis, not PostgreSQL
ENV['AUTHENTICATION_MODE'] = 'simple'

require_relative '../../../support/test_helpers'

OT.boot! :test, false

# Setup: create unique test emails for these tryouts
@email1 = generate_random_email
@email2 = generate_random_email
@email3 = generate_random_email
@email4 = generate_random_email

# Clear any existing role indexes to start with clean state
Onetime::Customer.role_index_for('colonel').clear rescue nil
Onetime::Customer.role_index_for('admin').clear rescue nil
Onetime::Customer.role_index_for('staff').clear rescue nil
Onetime::Customer.role_index_for('customer').clear rescue nil

# TRYOUTS

## Customer responds to find_all_by_role
Onetime::Customer.respond_to?(:find_all_by_role)
#=> true

## Customer responds to role_index_for
Onetime::Customer.respond_to?(:role_index_for)
#=> true

## role_index_for returns a Familia::Set or SortedSet
index = Onetime::Customer.role_index_for('colonel')
index.class.ancestors.any? { |a| a.to_s.include?('Familia') }
#=> true

## New customer has default role of 'customer'
@cust1 = Onetime::Customer.new(email: @email1)
@cust1.role
#=> 'customer'

## Saving customer with colonel role adds to colonel index
@cust1.role = 'colonel'
@cust1.joined = Familia.now.to_i - 3600  # 1 hour ago
@cust1.save
Onetime::Customer.role_index_for('colonel').member?(@cust1.identifier)
#=> true

## Customer is NOT in other role indexes after save
Onetime::Customer.role_index_for('admin').member?(@cust1.identifier)
#=> false

## Saving a second colonel adds to colonel index
@cust2 = Onetime::Customer.new(email: @email2)
@cust2.role = 'colonel'
@cust2.joined = Familia.now.to_i - 1800  # 30 min ago (newer than cust1)
@cust2.save
Onetime::Customer.role_index_for('colonel').member?(@cust2.identifier)
#=> true

## find_all_by_role returns array of customers
colonels = Onetime::Customer.find_all_by_role('colonel')
colonels.is_a?(Array)
#=> true

## find_all_by_role returns correct number of colonels
Onetime::Customer.find_all_by_role('colonel').size
#=> 2

## find_all_by_role returns Customer instances
Onetime::Customer.find_all_by_role('colonel').first.is_a?(Onetime::Customer)
#=> true

## find_all_by_role returns empty array when no customers with role
Onetime::Customer.find_all_by_role('nonexistent_role')
#=> []

## Changing role from colonel to customer updates indexes
@cust2.role = 'customer'
@cust2.save
Onetime::Customer.role_index_for('colonel').member?(@cust2.identifier)
#=> false

## Customer is now in customer role index after role change
Onetime::Customer.role_index_for('customer').member?(@cust2.identifier)
#=> true

## colonel_count returns correct count (backward-compatible method)
Onetime::Customer.colonel_count
#=> 1

## Changing role back to colonel adds to colonel index again
@cust2.role = 'colonel'
@cust2.save
Onetime::Customer.role_index_for('colonel').member?(@cust2.identifier)
#=> true

## Customer is no longer in customer role index
Onetime::Customer.role_index_for('customer').member?(@cust2.identifier)
#=> false

## Create third colonel with earliest joined date
@cust3 = Onetime::Customer.new(email: @email3)
@cust3.role = 'colonel'
@cust3.joined = Familia.now.to_i - 7200  # 2 hours ago (oldest)
@cust3.save
Onetime::Customer.find_all_by_role('colonel').size
#=> 3

## find_first_colonel returns oldest colonel by joined date
first_colonel = Onetime::Customer.find_first_colonel
first_colonel.identifier == @cust3.identifier
#=> true

## list_colonels returns array sorted by joined date (oldest first)
colonels = Onetime::Customer.list_colonels
colonels.first.identifier == @cust3.identifier
#=> true

## list_colonels returns all colonels
Onetime::Customer.list_colonels.size
#=> 3

## list_colonels second entry is cust1 (middle joined date)
colonels = Onetime::Customer.list_colonels
colonels[1].identifier == @cust1.identifier
#=> true

## list_colonels last entry is cust2 (newest joined date)
colonels = Onetime::Customer.list_colonels
colonels.last.identifier == @cust2.identifier
#=> true

## Destroying customer removes from role index
cust3_id = @cust3.identifier
@cust3.destroy!
Onetime::Customer.role_index_for('colonel').member?(cust3_id)
#=> false

## Colonel count decreases after destroy
Onetime::Customer.colonel_count
#=> 2

## find_first_colonel returns next oldest after destroy
first_colonel = Onetime::Customer.find_first_colonel
first_colonel.identifier == @cust1.identifier
#=> true

## Works for admin role - create admin customer
@cust4 = Onetime::Customer.new(email: @email4)
@cust4.role = 'admin'
@cust4.joined = Familia.now.to_i
@cust4.save
Onetime::Customer.find_all_by_role('admin').size
#=> 1

## find_all_by_role for admin returns correct customer
Onetime::Customer.find_all_by_role('admin').first.identifier == @cust4.identifier
#=> true

## Multiple role indexes work independently
Onetime::Customer.find_all_by_role('colonel').size
#=> 2

## find_first_colonel returns nil when no colonels exist
@cust1.role = 'customer'
@cust1.save
@cust2.role = 'customer'
@cust2.save
Onetime::Customer.role_index_for('colonel').clear
Onetime::Customer.find_first_colonel
#=> nil

## colonel_count returns 0 when no colonels
Onetime::Customer.colonel_count
#=> 0

## list_colonels returns empty array when no colonels
Onetime::Customer.list_colonels
#=> []

# TEARDOWN

# Clean up test customers
[@cust1, @cust2, @cust4].each do |cust|
  begin
    cust.delete! if cust&.exists?
  rescue StandardError
    nil
  end
end

# Clear role indexes
Onetime::Customer.role_index_for('colonel').clear rescue nil
Onetime::Customer.role_index_for('admin').clear rescue nil
Onetime::Customer.role_index_for('staff').clear rescue nil
Onetime::Customer.role_index_for('customer').clear rescue nil
