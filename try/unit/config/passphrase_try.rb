# try/23_passphrase_try.rb
#
# frozen_string_literal: true

# These tryouts test the functionality of passphrase handling in the Onetime application.
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


require_relative '../../support/test_models'

#Familia.debug = false

OT.boot! :test, false

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

secret_identifier = s.identifier
s2 = Onetime::Secret.find_by_identifier secret_identifier

[s2.passphrase_encryption, s2.passphrase?('plop')]
#=> ["1", true]

## Calling update_passphrase (without bang) automatically saves the passphrase too
s = Onetime::Secret.new :shared
s.update_passphrase 'plop'

secret_identifier = s.identifier
s2 = Onetime::Secret.find_by_identifier secret_identifier

[s2.passphrase_encryption, s2.passphrase?('plop')]
#=> ["1", true]
