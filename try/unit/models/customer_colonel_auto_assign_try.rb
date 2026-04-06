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
# 6. ensure_colonel_role: promotion, demotion, admin guard, no-op

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

## With comma-separated colonels: colonels_list splits and normalizes
set_colonels(['first@test.example.com,SECOND@TEST.EXAMPLE.COM'])
list = @colonel_assignment.colonels_list
list.include?('first@test.example.com') && list.include?('second@test.example.com')
#=> true

## With comma-separated colonels: colonel? matches individual emails
set_colonels(['first@test.example.com,second@test.example.com'])
@colonel_assignment.colonel?('second@test.example.com')
#=> true

## With mixed array and comma-separated: all emails are found
set_colonels(['solo@test.example.com', 'pair1@test.example.com,pair2@test.example.com'])
list = @colonel_assignment.colonels_list
list.size == 3 && list.include?('solo@test.example.com') && list.include?('pair1@test.example.com') && list.include?('pair2@test.example.com')
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

## ensure_colonel_role promotes customer to colonel when email is in list
@promote_email = "promote-#{SecureRandom.hex(4)}@test.example.com"
set_colonels([@promote_email])
@promote_cust = Onetime::Customer.create!(email: @promote_email)
@promote_cust.role = 'customer'
@promote_cust.save
@colonel_assignment.ensure_colonel_role(@promote_cust, context: 'test')
#=> :promoted

## ensure_colonel_role sets role to colonel after promotion
@promote_cust.role
#=> 'colonel'

## ensure_colonel_role demotes colonel when email is NOT in list
@demote_email = "demote-#{SecureRandom.hex(4)}@test.example.com"
set_colonels(['someone-else@test.example.com'])
@demote_cust = Onetime::Customer.create!(email: @demote_email)
@demote_cust.role = 'colonel'
@demote_cust.save
@colonel_assignment.ensure_colonel_role(@demote_cust, context: 'test')
#=> :demoted

## ensure_colonel_role sets role to customer after demotion
@demote_cust.role
#=> 'customer'

## ensure_colonel_role never touches admin role even when email is in list
@admin_email = "admin-guard-#{SecureRandom.hex(4)}@test.example.com"
set_colonels([@admin_email])
@admin_cust = Onetime::Customer.create!(email: @admin_email)
@admin_cust.role = 'admin'
@admin_cust.save
@colonel_assignment.ensure_colonel_role(@admin_cust, context: 'test').nil?
#=> true

## ensure_colonel_role preserves admin role
@admin_cust.role
#=> 'admin'

## ensure_colonel_role returns nil when already correct (colonel in list)
@noop_email = "noop-#{SecureRandom.hex(4)}@test.example.com"
set_colonels([@noop_email])
@noop_cust = Onetime::Customer.create!(email: @noop_email)
@noop_cust.role = 'colonel'
@noop_cust.save
@colonel_assignment.ensure_colonel_role(@noop_cust, context: 'test').nil?
#=> true

## ensure_colonel_role returns nil when already correct (customer not in list)
@noop2_email = "noop2-#{SecureRandom.hex(4)}@test.example.com"
set_colonels(['other@test.example.com'])
@noop2_cust = Onetime::Customer.create!(email: @noop2_email)
@colonel_assignment.ensure_colonel_role(@noop2_cust, context: 'test').nil?
#=> true

## ensure_colonel_role returns nil for nil customer
@colonel_assignment.ensure_colonel_role(nil, context: 'test').nil?
#=> true

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
[@colonel_cust, @regular_cust, @promote_cust, @demote_cust, @admin_cust, @noop_cust, @noop2_cust].compact.each do |cust|
  begin
    cust.delete! if cust&.exists?
  rescue StandardError
    nil
  end
end

# Restore original config
set_colonels(@original_colonels)
