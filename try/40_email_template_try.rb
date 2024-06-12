# frozen_string_literal: true

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot!

@cust = OT::Customer.new :tryouts
@secret = OT::Secret.new :tryouts
@locale = 'es'

## Can create a view
view = OT::Email::Welcome.new @cust, @locale, @secret
puts view.render
[view.verify_uri, view[:secret]]
true
#=> true

## Can create a view
view = OT::Email::SecretLink.new @cust, @locale, @secret, 'tryouts@onetime.com'
puts view.render
[view.verify_uri, view[:secret], view.subject]
true
#=> true

## Understands locale in english
view = OT::Email::SecretLink.new @cust, 'en', @secret, 'tryouts@onetime.com'
view.subject
#=> 'CHANGEME@example.com sent you a secret'

## Understands locale in spanish
view = OT::Email::SecretLink.new @cust, 'es', @secret, 'tryouts@onetime.com'
view.subject
#=> 'CHANGEME@example.com le ha enviado un secreto'
