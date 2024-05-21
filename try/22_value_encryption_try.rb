# frozen_string_literal: true

require_relative '../lib/onetime'

OT.load! :app

## Has global secret
Onetime.global_secret.nil?
#=> false

## Has default global secret
Onetime.global_secret
#=> 'CHANGEME'

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
#=> 'cf45ffd1d3f709719411ed2d4b185fa09056fb83'

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
rescue => ex
  ex.class
end
#=> OpenSSL::Cipher::CipherError


Onetime::Secret.new(:shared).destroy!
