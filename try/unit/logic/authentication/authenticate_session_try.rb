# try/unit/logic/authentication/authenticate_session_try.rb
#
# frozen_string_literal: true

# These tests cover the AuthenticateSession logic class which handles
# session authentication.

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

# Setup a customer with argon2 password
@auth_email = generate_unique_test_email("auth_session")
@auth_cust = Customer.create!(email: @auth_email)
@auth_cust.update_passphrase(@testpass)
@auth_cust.save

## Customer has argon2 hash (passphrase_encryption = '2')
@auth_cust.passphrase_encryption
#=> '2'

## Argon2 hash is detected correctly
@auth_cust.argon2_hash?(@auth_cust.passphrase)
#=> true

## Password verification works
@auth_cust.passphrase?(@testpass)
#=> true

## BCrypt password can still be verified (backwards compatibility)
@bcrypt_cust = Customer.create!(email: generate_unique_test_email("bcrypt_migration"))
@bcrypt_cust.passphrase = BCrypt::Password.create('bcrypt-pass-123', cost: 4).to_s
@bcrypt_cust.passphrase_encryption = '1'
@bcrypt_cust.save
@bcrypt_cust.passphrase?('bcrypt-pass-123')
#=> true

## BCrypt hash is not detected as argon2
@bcrypt_cust.argon2_hash?(@bcrypt_cust.passphrase)
#=> false

## BCrypt password can be migrated to argon2
@bcrypt_cust.update_passphrase('bcrypt-pass-123')
@bcrypt_cust.save
@bcrypt_cust.argon2_hash?(@bcrypt_cust.passphrase)
#=> true

## Migrated password still verifies
@bcrypt_cust.passphrase?('bcrypt-pass-123')
#=> true

## Migrated password has encryption mode '2'
@bcrypt_cust.passphrase_encryption
#=> '2'

## Pending-verification login message echoes the email address, not the objid (QS-13)
@pending_email = generate_unique_test_email("pending_login")
@pending_cust = Customer.create!(email: @pending_email)
@pending_cust.update_passphrase(@testpass)
@pending_cust.verified = false
@pending_cust.role = 'customer'
@pending_cust.save
strategy_result = MockStrategyResult.new(session: {})
logic = Auth::AuthenticateSession.new(strategy_result, { 'login' => @pending_email, 'password' => @testpass }, 'en')
logic.raise_concerns
captured = StringIO.new
original_stderr = $stderr
$stderr = captured
begin
  logic.process
ensure
  $stderr = original_stderr
end
msg_line = captured.string.lines.find { |line| line.include?('sent to') }
[msg_line&.include?(@pending_email), msg_line&.include?(@pending_cust.objid)]
#=> [true, false]
