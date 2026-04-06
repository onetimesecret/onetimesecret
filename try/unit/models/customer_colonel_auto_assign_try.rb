# try/unit/models/customer_colonel_auto_assign_try.rb
#
# frozen_string_literal: true

# Tests for colonel list utilities.
#
# Covers:
# 1. colonels_list returns normalized emails from config
# 2. colonel? checks if email is in the colonels list
# 3. Case-insensitive email matching (Unicode case folding)
# 4. Empty/nil colonels list handling
# 5. Whitespace handling in config and email
# 6. Comma-separated values in config entries

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
@colonel_assignment.respond_to?(:colonel?)
#=> true

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

## With empty colonels list: colonel? returns false
set_colonels([])
@colonel_assignment.colonel?('anyone@test.example.com')
#=> false

## With nil colonels list: colonel? returns false
set_colonels(nil)
@colonel_assignment.colonel?('anyone@test.example.com')
#=> false

## colonel? returns false for nil email
@colonel_assignment.colonel?(nil)
#=> false

## colonel? returns false for empty email
@colonel_assignment.colonel?('')
#=> false

# TEARDOWN

# Restore original config
set_colonels(@original_colonels)
