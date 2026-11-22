# try/unit/config/strict_keys_try.rb
#
# frozen_string_literal: true

# Tryouts run with Onetime::Config::StrictKeys on, as specs do: the test
# helpers turn it on, and every Hash in the booted config raises on a
# non-String key. Without it, a Symbol read on a config section in a tryout
# reads nil without an error.

require_relative '../../support/test_helpers'

OT.boot! :test, false

## The test helpers turn StrictKeys on
Onetime::Config.strict_keys?
#=> true

## The booted config has StrictKeys
OT.conf.is_a?(Onetime::Config::StrictKeys)
#=> true

## A Symbol read on a section raises
begin
  OT.conf.get('site')[:host]
  :no_error
rescue Onetime::Config::KeyTypeError => e
  e.key
end
#=> :host

## A String read on a section reads as on a plain Hash
OT.conf.get('site')['host'] == OT.conf.get('site.host')
#=> true
