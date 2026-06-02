# try/unit/models/argon2_passphrase_try.rb
#
# frozen_string_literal: true

# These tryouts test the passphrase hashing implementation
# in the PassphraseHashing feature module.
#
# Tests cover:
# 1. Creating argon2 password hashes (default)
# 2. Verifying argon2 hashes
# 3. Verifying bcrypt hashes (backwards compatibility)
# 4. Hash algorithm detection
# 5. Customer dummy using argon2

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Setup
@test_password = 'test-password-12345'

# Create test customer
@argon2_customer = Onetime::Customer.new(email: generate_random_email)

# TRYOUTS

## New password hash uses argon2id by default
@argon2_customer.update_passphrase(@test_password)
@argon2_customer.passphrase.start_with?('$argon2id$')
#=> true

## Argon2 sets passphrase_encryption to '2'
@argon2_customer.passphrase_encryption
#=> '2'

## Argon2 hash is detected correctly
@argon2_customer.argon2_hash?(@argon2_customer.passphrase)
#=> true

## Argon2 password verification works
@argon2_customer.passphrase?(@test_password)
#=> true

## Argon2 password verification rejects wrong password
@argon2_customer.passphrase?('wrong-password')
#=> false

## BCrypt password verification still works (backwards compatibility)
@bcrypt_customer = Onetime::Customer.new(email: generate_random_email)
@bcrypt_customer.passphrase = BCrypt::Password.create('bcrypt-pass', cost: 4).to_s
@bcrypt_customer.passphrase_encryption = '1'
@bcrypt_customer.passphrase?('bcrypt-pass')
#=> true

## BCrypt password verification rejects wrong password
@bcrypt_customer.passphrase?('wrong-password')
#=> false

## Empty passphrase returns false (DoS prevention)
empty_cust = Onetime::Customer.new(email: generate_random_email)
empty_cust.passphrase?('anything')
#=> false

## has_passphrase? works for argon2
@argon2_customer.has_passphrase?
#=> true

## Customer.dummy uses argon2
Onetime::Customer.instance_variable_set(:@dummy, nil) # Reset cached dummy
@dummy = Onetime::Customer.dummy
@dummy.passphrase.start_with?('$argon2id$')
#=> true

## Customer.dummy has passphrase_encryption = '2'
@dummy.passphrase_encryption
#=> '2'

## Customer.dummy is frozen
@dummy.frozen?
#=> true

## argon2_hash_cost returns test cost in test environment
with_env('RACK_ENV', 'test') { @argon2_customer.argon2_hash_cost }
#=> { t_cost: 1, m_cost: 5, p_cost: 1 }
