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
#=> '\x8D\xF2k\xD0;\xB9\xB5\xC3\x02+@\xEA\x06\xA2+\xA9'

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