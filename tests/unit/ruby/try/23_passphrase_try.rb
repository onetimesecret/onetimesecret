# tests/unit/ruby/try/23_passphrase_try.rb

# These tryouts test the functionality of passphrase handling in the OneTime application.
# Specifically, they focus on:
#
# 1. Storing a plaintext passphrase
# 2. Storing and verifying a one-way encrypted passphrase
#
# These tests aim to ensure that passphrases are correctly stored and verified,
# which is crucial for maintaining the security of secrets in the application.
#
# The tryouts use the V2::Secret class to demonstrate passphrase-related operations,
# allowing for targeted testing of these specific scenarios without needing to run the full application.


require_relative './test_helpers'
#Familia.debug = false

# Use the default config file for tests
OT.boot! :test

## Can store a passphrase
s = V2::Secret.new :shared
s.passphrase = 'plop'
s.passphrase
#=> 'plop'

## Can store a one-way, encrypted passphrase
s = V2::Secret.new :shared
s.update_passphrase 'plop'
[s.passphrase_encryption, s.passphrase?('plop')]
#=> ["1", true]

## Calling update_passphrase! automatically saves the passphrase
s = V2::Secret.new :shared
s.update_passphrase! 'plop'

secret_key = s.identifier
s2 = V2::Secret.from_identifier secret_key

[s2.passphrase_encryption, s2.passphrase?('plop')]
#=> ["1", true]

## Calling update_passphrase (without bang) automatically saves the passphrase too
s = V2::Secret.new :shared
s.update_passphrase 'plop'

secret_key = s.identifier
s2 = V2::Secret.from_identifier secret_key

[s2.passphrase_encryption, s2.passphrase?('plop')]
#=> ["1", true]
