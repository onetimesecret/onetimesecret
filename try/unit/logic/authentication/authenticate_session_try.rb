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
