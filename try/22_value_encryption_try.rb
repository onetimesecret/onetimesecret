# frozen_string_literal: true

# These tryouts test the encryption and decryption functionality
# of the Onetime::Secret class.
#
# We're testing various aspects of secret handling, including:
# 1. Storing a value
# 2. Encrypting a value
# 3. Decrypting a value
# 4. Behavior when decrypting without prior encryption
# 5. Behavior when the global secret is changed
#
# These tests aim to ensure that the secret handling mechanism
# in the Onetime application works correctly and securely, which
# is crucial for the core functionality of the service.
#
# The tryouts simulate different scenarios of secret handling
# without needing to run the full application, allowing for
# targeted testing of this specific functionality.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

## Can store a value
s = Onetime::Secret.new :shared
s.value = 'poop'
s.value
#=> 'poop'

## Can encrypt a value
s = Onetime::Secret.new :shared
s.encrypt_value 'poop', key: 'tryouts'
puts "These values should match character for character. Not sure why they don't :-?"
s.value.gibbler
#=> '0bed39f588f66da4d40636d64b830871d8816cbc'

## Can decrypt a value
s = Onetime::Secret.new :shared
s.encrypt_value 'poop', key: 'tryouts'
s.decrypted_value
#=> 'poop'

## Decrypt does nothing if encrypt_value wasn't called
s = Onetime::Secret.new :shared2
s.value = 'poop'
s.decrypted_value
#=> 'poop'

## Cannot decrypt after changing global secret
s = Onetime::Secret.new :shared
s.encrypt_value 'poop', key: 'tryouts'
Onetime.instance_variable_set(:@global_secret, 'NEWVALUE')
begin
  s.decrypted_value
rescue StandardError => e
  e.class
end
#=> OpenSSL::Cipher::CipherError

Onetime::Secret.new(:shared).destroy!
