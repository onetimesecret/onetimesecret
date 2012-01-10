require 'onetime'


## Can store a value
s = Onetime::Secret.new :shared
s.value = 'poop'
s.value
#=> 'poop'

## Can encrypt a value
s = Onetime::Secret.new :shared
s.encrypt_value 'poop', :key => 'tryouts'
puts "These values should match character for character. Not sure why they don't :-?"
s.value
#=> '\xEF\xDF\xAEt\xAF\xD6\f\x15oZ\x9E\xB8a\xF1\x9E/'

## Can decrypt a value
s = Onetime::Secret.new :shared
s.encrypt_value 'poop', :key => 'tryouts'
s.decrypted_value
#=> 'poop'

## Decrypt does nothing if encrypt_value wasn't called
s = Onetime::Secret.new :shared2
s.value = 'poop'
s.decrypted_value
#=> 'poop'


Onetime::Secret.new(:shared).destroy!