# try/22_value_encryption_try.rb

# These tryouts test the encryption and decryption functionality
# of the V2::Secret class.
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

require_relative 'test_models'
OT.boot! :test, false

## Can store a value
s = V2::Secret.new :shared
s.value = 'poop'
s.value
#=> 'poop'

## Can encrypt a value
s = V2::Secret.new :shared
s.encrypt_value 'poop', key: 'tryouts'
puts "The value checksum is the gibbled value after being truncated (if needed)"
s.value_checksum
#=> 'cffab3469f0aec11d52c4b24882fb6f77149b7b7'

## Can decrypt a value
s = V2::Secret.new :shared
s.encrypt_value 'poop', key: 'tryouts'
s.decrypted_value
#=> 'poop'

## Decrypt does nothing if encrypt_value wasn't called
s = V2::Secret.new :shared2
s.value = 'poop'
s.decrypted_value
#=> 'poop'

## Cannot decrypt after changing global secret
s = V2::Secret.new :shared
s.encrypt_value 'poop', key: 'tryouts'
Onetime.instance_variable_set(:@global_secret, 'NEWVALUE')
begin
  s.decrypted_value
rescue StandardError => e
  e.class
end
#=> OpenSSL::Cipher::CipherError

V2::Secret.new(:shared).destroy!
