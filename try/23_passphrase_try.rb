# frozen_string_literal: true

# These tryouts test the functionality of passphrase handling in the OneTime application.
# Specifically, they focus on:
#
# 1. Storing a plaintext passphrase
# 2. Storing and verifying a one-way encrypted passphrase
#
# These tests aim to ensure that passphrases are correctly stored and verified,
# which is crucial for maintaining the security of secrets in the application.
#
# The tryouts use the Onetime::Secret class to demonstrate passphrase-related operations,
# allowing for targeted testing of these specific scenarios without needing to run the full application.


require_relative '../lib/onetime'
Familia.debug = false

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

## Can store a passphrase
s = Onetime::Secret.new :shared
s.passphrase = 'plop'
s.passphrase
#=> 'plop'

## Can store a one-way, encrypted passphrase
s = Onetime::Secret.new :shared
s.update_passphrase 'plop'
[s.passphrase_encryption, s.passphrase?('plop')]
#=> ["1", true]

## Calling update_passphrase! automatically saves the passphrase
s = Onetime::Secret.new :shared
s.update_passphrase! 'plop'

secret_key = s.identifier
s2 = Onetime::Secret.from_identifier secret_key

[s2.passphrase_encryption, s2.passphrase?('plop')]
#=> ["1", true]

## Calling update_passphrase (without bang) automatically saves the passphrase too
s = Onetime::Secret.new :shared
s.update_passphrase 'plop'

secret_key = s.identifier
s2 = Onetime::Secret.from_identifier secret_key

[s2.passphrase_encryption, s2.passphrase?('plop')]
#=> ["1", true]
