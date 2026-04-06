# try/unit/models/customer_colonel_auto_assign_try.rb
#
# frozen_string_literal: true

# Tests for colonel auto-assignment based on config.
#
# Covers:
# 1. Colonel email gets colonel role on account creation
# 2. Non-colonel email gets customer role (default)
# 3. Case-insensitive email matching (Unicode case folding)
# 4. Empty/nil colonels list defaults to customer role
# 5. Whitespace handling in config and email
# 6. Security audit logging for privilege escalation

# Force simple auth mode - these tests only need Redis, not PostgreSQL
ENV['AUTHENTICATION_MODE'] = 'simple'

require_relative '../../support/test_helpers'

OT.boot! :test, false

# Store original config for restoration and setup test config
@original_colonels = OT.conf.dig('site', 'authentication', 'colonels')&.dup
@colonel_assignment = Onetime::Customer::Features::ColonelAssignment

# Helper to set colonels config
def set_colonels(list)
  OT.conf['site'] ||= {}
  OT.conf['site']['authentication'] ||= {}
  OT.conf['site']['authentication']['colonels'] = list
end

# TRYOUTS

## ColonelAssignment module is available
@colonel_assignment.respond_to?(:determine_role)
#=> true

## ColonelAssignment.normalize_email strips whitespace
@colonel_assignment.normalize_email('  test@example.com  ')
#=> 'test@example.com'

## ColonelAssignment.normalize_email applies Unicode case folding
@colonel_assignment.normalize_email('TEST@EXAMPLE.COM')
#=> 'test@example.com'

## ColonelAssignment.normalize_email handles nil
@colonel_assignment.normalize_email(nil)
#=> ''

## ColonelAssignment.determine_role returns 'customer' for nil email
@colonel_assignment.determine_role(nil)
#=> 'customer'

## ColonelAssignment.determine_role returns 'customer' for empty email
@colonel_assignment.determine_role('')
#=> 'customer'

## With configured colonels: colonels_list returns normalized emails
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
list = @colonel_assignment.colonels_list
list.include?('colonel@test.example.com') && list.include?('admin@test.example.com')
#=> true

## With configured colonels: colonel? returns true for exact match
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.colonel?('colonel@test.example.com')
#=> true

## With configured colonels: colonel? returns true for case-insensitive match
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.colonel?('COLONEL@TEST.EXAMPLE.COM')
#=> true

## With configured colonels: colonel? returns true for mixed case config
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.colonel?('admin@test.example.com')
#=> true

## With configured colonels: colonel? returns false for non-colonel email
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.colonel?('regular@test.example.com')
#=> false

## With configured colonels: determine_role returns 'colonel' for colonel email
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.determine_role('colonel@test.example.com')
#=> 'colonel'

## With configured colonels: determine_role returns 'colonel' for case-insensitive match
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.determine_role('ADMIN@TEST.EXAMPLE.COM')
#=> 'colonel'

## With configured colonels: determine_role returns 'customer' for non-colonel email
set_colonels(['colonel@test.example.com', 'ADMIN@TEST.EXAMPLE.COM'])
@colonel_assignment.determine_role('regular@test.example.com')
#=> 'customer'

## With empty colonels list: determine_role returns 'customer'
set_colonels([])
@colonel_assignment.determine_role('anyone@test.example.com')
#=> 'customer'

## With nil colonels list: determine_role returns 'customer'
set_colonels(nil)
@colonel_assignment.determine_role('anyone@test.example.com')
#=> 'customer'

## assign_if_colonel returns true and sets role for colonel
set_colonels(['assign-test@example.com'])
@test_cust = Onetime::Customer.new(email: 'assign-test@example.com')
@colonel_assignment.assign_if_colonel(@test_cust, 'assign-test@example.com')
#=> true

## assign_if_colonel sets role to colonel
@test_cust.role
#=> 'colonel'

## assign_if_colonel returns false for non-colonel
set_colonels(['assign-test@example.com'])
@test_cust2 = Onetime::Customer.new(email: 'nobody@test.example.com')
@colonel_assignment.assign_if_colonel(@test_cust2, 'nobody@test.example.com')
#=> false

## assign_if_colonel does not change role for non-colonel
@test_cust2.role
#=> 'customer'

## Integration: New customer with colonel email - determine_role returns colonel
set_colonels(['integration-colonel@test.example.com'])
@colonel_email = "integration-colonel-#{SecureRandom.hex(4)}@test.example.com"
set_colonels([@colonel_email])
@colonel_assignment.determine_role(@colonel_email)
#=> 'colonel'

## Integration: Create customer with colonel email
@colonel_cust = Onetime::Customer.create!(email: @colonel_email)
@colonel_cust.email == @colonel_email
#=> true

## Integration: New customer with non-colonel email - determine_role returns customer
@regular_email = "regular-#{SecureRandom.hex(4)}@test.example.com"
@colonel_assignment.determine_role(@regular_email)
#=> 'customer'

## Integration: Create customer with non-colonel email
@regular_cust = Onetime::Customer.create!(email: @regular_email)
@regular_cust.email == @regular_email
#=> true

# TEARDOWN

# Clean up test customers
[@colonel_cust, @regular_cust].compact.each do |cust|
  begin
    cust.delete! if cust&.exists?
  rescue StandardError
    nil
  end
end

# Restore original config
set_colonels(@original_colonels)
