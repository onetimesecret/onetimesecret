# apps/web/auth/try/operations/migrate_password_from_redis_try.rb
#
# frozen_string_literal: true

# MigratePasswordFromRedis Operation Test Suite
#
# Tests password verification against Redis Customer records during
# migration from simple auth mode to full auth mode.

ENV['RACK_ENV'] = 'test'

require_relative '../../../../../try/support/test_helpers'

require 'onetime'

OT.boot! :test, false

require_relative '../../operations/migrate_password_from_redis'

# Create a test customer with bcrypt password
@test_email_bcrypt = generate_unique_test_email('migrate_bcrypt')
@test_password = 'test_password_123'

@customer_bcrypt = Onetime::Customer.create!(
  email: @test_email_bcrypt,
  role: 'customer',
  verified: false
)
@customer_bcrypt.update_passphrase(@test_password, algorithm: :bcrypt)
@customer_bcrypt.save

# Create a test customer with argon2 password
@test_email_argon2 = generate_unique_test_email('migrate_argon2')

@customer_argon2 = Onetime::Customer.create!(
  email: @test_email_argon2,
  role: 'customer',
  verified: false
)
@customer_argon2.update_passphrase(@test_password, algorithm: :argon2)
@customer_argon2.save

# Create a test customer without password (OAuth-only user)
@test_email_no_password = generate_unique_test_email('migrate_nopass')

@customer_no_password = Onetime::Customer.create!(
  email: @test_email_no_password,
  role: 'customer',
  verified: false
)
# No passphrase set

## MigratePasswordFromRedis verifies bcrypt password successfully
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_bcrypt,
  password: @test_password
).call
result.success?
#=> true

## MigratePasswordFromRedis returns customer on successful bcrypt verification
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_bcrypt,
  password: @test_password
).call
result.customer.email
#=> @test_email_bcrypt

## MigratePasswordFromRedis verifies argon2 password successfully
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_argon2,
  password: @test_password
).call
result.success?
#=> true

## MigratePasswordFromRedis returns customer on successful argon2 verification
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_argon2,
  password: @test_password
).call
result.customer.email
#=> @test_email_argon2

## MigratePasswordFromRedis fails with wrong password for bcrypt
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_bcrypt,
  password: 'wrong_password'
).call
result.success?
#=> false

## MigratePasswordFromRedis returns password_mismatch reason for wrong password
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_bcrypt,
  password: 'wrong_password'
).call
result.reason
#=> :password_mismatch

## MigratePasswordFromRedis fails with wrong password for argon2
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_argon2,
  password: 'wrong_password'
).call
result.success?
#=> false

## MigratePasswordFromRedis fails for non-existent customer
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: 'nonexistent@example.com',
  password: @test_password
).call
result.success?
#=> false

## MigratePasswordFromRedis returns customer_not_found for non-existent email
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: 'nonexistent@example.com',
  password: @test_password
).call
result.reason
#=> :customer_not_found

## MigratePasswordFromRedis fails for customer without passphrase
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_no_password,
  password: @test_password
).call
result.success?
#=> false

## MigratePasswordFromRedis returns no_passphrase for customer without password
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: @test_email_no_password,
  password: @test_password
).call
result.reason
#=> :no_passphrase

## MigratePasswordFromRedis result has failed? method
result = Auth::Operations::MigratePasswordFromRedis.new(
  email: 'nonexistent@example.com',
  password: @test_password
).call
result.failed?
#=> true

# Teardown - Clean up test customers
@customer_bcrypt.destroy!
@customer_argon2.destroy!
@customer_no_password.destroy!
