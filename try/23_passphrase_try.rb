require 'onetime'


## Can store a passphrase
s = Onetime::Secret.new :shared
s.passphrase = "poop"
s.passphrase
#=> 'poop'

## Can store a one-way, encrypted passphrase
s = Onetime::Secret.new :shared
s.update_passphrase "poop"
[s.passphrase_encryption, s.passphrase?('poop')]
#=> [1, true]

