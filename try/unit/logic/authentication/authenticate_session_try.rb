# try/unit/logic/authentication/authenticate_session_try.rb
#
# frozen_string_literal: true

# These tests cover the AuthenticateSession logic class which handles
# session authentication and transparent password hash migration.
#
# We test:
# 1. Session authentication basics
# 2. Password hash migration (bcrypt → argon2) on successful login
# 3. Migration idempotency
# 4. Failed logins don't trigger migration

require_relative '../../../support/test_logic'

# Load the app with test configuration
OT.boot! :test, true

# Load Core::Logic::Authentication which contains AuthenticateSession
require 'web/core/logic/authentication'

# Alias for cleaner test code
Auth = Core::Logic::Authentication

# Setup common test variables
@now = Familia.now
@testpass = 'test-password-12345'

# TRYOUTS

# Password Hash Migration Tests
#
# These tests verify that bcrypt passwords are transparently migrated to argon2
# on successful login, as implemented in migrate_password_hash_if_needed.

# Setup a customer with bcrypt password for migration tests
@migration_email = generate_unique_test_email("auth_migrate")
@migration_cust = Customer.create!(email: @migration_email)
@migration_cust.update_passphrase(@testpass, algorithm: :bcrypt)
@migration_cust.save

## Customer starts with bcrypt hash (passphrase_encryption = '1')
@migration_cust.passphrase_encryption
#=> '1'

## Bcrypt hash is not detected as argon2
@migration_cust.argon2_hash?(@migration_cust.passphrase)
#=> false

## Bcrypt password verification works before migration
@migration_cust.passphrase?(@testpass)
#=> true

## Successful login migrates bcrypt password to argon2
@migration_session = {}
@migration_strategy = MockStrategyResult.new(session: @migration_session, user: nil, metadata: { ip: '127.0.0.1' })
@migration_params = { 'login' => @migration_email, 'password' => @testpass, 'stay' => 'true' }
@auth_migration = Auth::AuthenticateSession.new @migration_strategy, @migration_params

# Reload customer to see the updated password hash
@migration_cust_after = Customer.find_by_email(@migration_email)
@migration_cust_after.passphrase_encryption
#=> '2'

## After migration, hash is argon2 format
@migration_cust_after.argon2_hash?(@migration_cust_after.passphrase)
#=> true

## Password still works after migration
@migration_cust_after.passphrase?(@testpass)
#=> true

## Migration is idempotent - second login doesn't change hash
@original_hash = @migration_cust_after.passphrase
@auth_migration2 = Auth::AuthenticateSession.new @migration_strategy, @migration_params
@migration_cust_after2 = Customer.find_by_email(@migration_email)
@migration_cust_after2.passphrase == @original_hash
#=> true

## Failed login does not trigger migration (setup new bcrypt customer)
@failed_email = generate_unique_test_email("auth_failed")
@failed_cust = Customer.create!(email: @failed_email)
@failed_cust.update_passphrase(@testpass, algorithm: :bcrypt)
@failed_cust.save
@failed_cust.passphrase_encryption == '1'
#=> true

## Failed login with wrong password does not migrate
@failed_session = {}
@failed_strategy = MockStrategyResult.new(session: @failed_session, user: nil, metadata: { ip: '127.0.0.1' })
@failed_params = { 'login' => @failed_email, 'password' => 'wrong_password', 'stay' => 'true' }
@auth_failed = Auth::AuthenticateSession.new @failed_strategy, @failed_params
@failed_cust_after = Customer.find_by_email(@failed_email)
@failed_cust_after.passphrase_encryption
#=> '1'

## Failed login leaves bcrypt hash unchanged
@failed_cust_after.argon2_hash?(@failed_cust_after.passphrase)
#=> false

## Successful login after previous failure does migrate
@correct_params = { 'login' => @failed_email, 'password' => @testpass, 'stay' => 'true' }
@auth_correct = Auth::AuthenticateSession.new @failed_strategy, @correct_params
@failed_cust_final = Customer.find_by_email(@failed_email)
@failed_cust_final.passphrase_encryption
#=> '2'

# Note: Test customers are left in the database for inspection if needed
