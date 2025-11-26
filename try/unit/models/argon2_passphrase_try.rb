# try/unit/models/argon2_passphrase_try.rb
#
# frozen_string_literal: true

# These tryouts test the argon2 password hashing implementation
# in the LegacyEncryptedFields feature module.
#
# Tests cover:
# 1. Creating argon2 password hashes (new default)
# 2. Creating bcrypt password hashes (legacy)
# 3. Verifying argon2 hashes
# 4. Verifying bcrypt hashes (backwards compatibility)
# 5. Hash algorithm detection
# 6. Customer dummy using argon2

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Setup
@test_password = 'test-password-12345'
@bcrypt_password = 'bcrypt-legacy-pass'

# Create test customers
@argon2_customer = Onetime::Customer.new(email: generate_random_email)
@bcrypt_customer = Onetime::Customer.new(email: generate_random_email)

# TRYOUTS

## New password hash uses argon2id by default
@argon2_customer.update_passphrase(@test_password)
@argon2_customer.passphrase.start_with?('$argon2id$')
#=> true

## Argon2 sets passphrase_encryption to '2'
@argon2_customer.passphrase_encryption
#=> '2'

## Can explicitly create bcrypt hash for legacy compatibility
@bcrypt_customer.update_passphrase(@bcrypt_password, algorithm: :bcrypt)
@bcrypt_customer.passphrase.start_with?('$2a$')
#=> true

## BCrypt sets passphrase_encryption to '1'
@bcrypt_customer.passphrase_encryption
#=> '1'

## Argon2 hash is detected correctly
@argon2_customer.argon2_hash?(@argon2_customer.passphrase)
#=> true

## BCrypt hash is not detected as argon2
@argon2_customer.argon2_hash?(@bcrypt_customer.passphrase)
#=> false

## Argon2 password verification works
@argon2_customer.passphrase?(@test_password)
#=> true

## Argon2 password verification rejects wrong password
@argon2_customer.passphrase?('wrong-password')
#=> false

## BCrypt password verification still works (backwards compatibility)
@bcrypt_customer.passphrase?(@bcrypt_password)
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

## has_passphrase? works for bcrypt
@bcrypt_customer.has_passphrase?
#=> true

## Customer.dummy uses argon2
Onetime::Customer.instance_variable_set(:@dummy, nil) # Reset cached dummy
dummy = Onetime::Customer.dummy
dummy.passphrase.start_with?('$argon2id$')
#=> true

## Customer.dummy has passphrase_encryption = '2'
dummy.passphrase_encryption
#=> '2'

## Customer.dummy is frozen
dummy.frozen?
#=> true

## argon2_hash_cost returns test cost in test environment
@argon2_customer.argon2_hash_cost
#=> { t_cost: 1, m_cost: 5, p_cost: 1 }

## Invalid algorithm raises ArgumentError
begin
  @argon2_customer.update_passphrase('test', algorithm: :invalid)
  false
rescue ArgumentError => e
  e.message.include?('Unknown password algorithm')
end
#=> true

## Complete migration workflow: bcrypt password migrates to argon2
migration_customer = Onetime::Customer.new(email: generate_random_email)
migration_password = 'migration-test-password'

# Start with bcrypt
migration_customer.update_passphrase(migration_password, algorithm: :bcrypt)
migration_customer.passphrase_encryption == '1' &&
migration_customer.argon2_hash?(migration_customer.passphrase) == false
#=> true

## Migration workflow: verify bcrypt password works
migration_customer.passphrase?(migration_password)
#=> true

## Migration workflow: rehash to argon2
migration_customer.update_passphrase!(migration_password)
migration_customer.passphrase_encryption
#=> '2'

## Migration workflow: new argon2 hash is valid
migration_customer.argon2_hash?(migration_customer.passphrase) &&
migration_customer.passphrase?(migration_password)
#=> true

# Cleanup - don't save these test customers
