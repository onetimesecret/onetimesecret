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

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot!

## Can store a passphrase
s = Onetime::Secret.new :shared
s.passphrase = 'poop'
s.passphrase
#=> 'poop'

## Can store a one-way, encrypted passphrase
s = Onetime::Secret.new :shared
s.update_passphrase 'poop'
[s.passphrase_encryption, s.passphrase?('poop')]
#=> ["1", true]
