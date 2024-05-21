# frozen_string_literal: true

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.load!

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
