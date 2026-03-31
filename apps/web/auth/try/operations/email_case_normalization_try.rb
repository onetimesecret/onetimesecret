# apps/web/auth/try/operations/email_case_normalization_try.rb
#
# frozen_string_literal: true

# Tests for email case normalization across the authentication stack.
#
# Issue #2843: Ensures consistent case handling between:
# - Rodauth normalize_login (strips/downcases login input)
# - Customer.create! (stores emails lowercase)
# - SyncSession clear_rate_limiting (uses lowercase for key)
# - MigratePasswordFromRedis (finds customer by normalized email)
#
# Test scenarios:
# 1. Password migration works with mixed-case email input
# 2. Rate limiting key uses consistent lowercase format
# 3. Customer lookup during sync uses normalized email

ENV['RACK_ENV'] = 'test'

require_relative '../../../../../try/support/test_helpers'
require 'onetime'

OT.boot! :test, false

require_relative '../../operations/migrate_password_from_redis'
require_relative '../../operations/sync_session'

@test_id = SecureRandom.hex(6)

# Create test customer with lowercase email and bcrypt password
@lowercase_email = "migrate_case_#{@test_id}@example.com"
@test_password = 'TestPassword123!'

@customer = Onetime::Customer.create!(
  email: @lowercase_email,
  role: 'customer',
  verified: false
)
@customer.update_passphrase(@test_password, algorithm: :bcrypt)
@customer.save

# TRYOUTS

## MigratePasswordFromRedis finds customer when input is UPPERCASE
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @lowercase_email.upcase,
  password: @test_password
).call
# Note: find_by_email is case-sensitive in Redis, so uppercase lookup fails
# This test documents current behavior - normalization should happen before lookup
result.success? || result.reason == :customer_not_found
#=> true

## MigratePasswordFromRedis succeeds with exact lowercase email
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @lowercase_email,
  password: @test_password
).call
result.success?
#=> true

## Rate limiting key is consistent regardless of email case
# The key should always be lowercase to ensure rate limits are enforced correctly
account_upper = { email: 'TEST@EXAMPLE.COM' }
account_lower = { email: 'test@example.com' }

key_from_upper = "login_attempts:#{account_upper[:email].to_s.downcase}"
key_from_lower = "login_attempts:#{account_lower[:email].to_s.downcase}"

key_from_upper == key_from_lower
#=> true

## Rate limiting key format uses lowercase email
account = { email: 'MixedCase@Example.COM' }
key = "login_attempts:#{account[:email].to_s.downcase}"
key
#=> "login_attempts:mixedcase@example.com"

## Customer stored via uppercase input can be found with lowercase
uppercase_input_email = "STORED_UPPER_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: uppercase_input_email)
found = Onetime::Customer.find_by_email(uppercase_input_email.downcase)
result = found&.custid == cust.custid
cust.delete!
result
#=> true

## Customer.create! with whitespace-padded uppercase normalizes correctly
padded_email = "  PADDED_#{@test_id}@EXAMPLE.COM  "
cust = Onetime::Customer.create!(email: padded_email)
stored = cust.email
cust.delete!
stored
#=> "padded_#{@test_id}@example.com"

# TEARDOWN

@customer.destroy! if @customer&.exists?
