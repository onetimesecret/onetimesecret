# try/unit/logic/secrets/conceal_secret_try.rb
#
# frozen_string_literal: true

# Tests for V1::Logic::Secrets::ConcealSecret param contract.
#
# Focus: the flat V1 HTTP params are passed directly to the logic class.
#
# V1 wire format:
#   POST /api/v1/share
#   secret=hello&ttl=3600&passphrase=pw
#
# Controller passes req.params flat to logic (no wrapping):
#   V1::Logic::Secrets::ConcealSecret.new(sess, cust, req.params, locale)
#
# BaseSecretAction#process_params:
#   @payload = params || {}
#   ConcealSecret#process_secret: @secret_value = payload['secret']
#

require_relative '../../../support/test_helpers'

OT.boot! :test, false

require 'v1/logic'

@email = generate_unique_test_email("conceal_secret")
@cust = Onetime::Customer.create!(email: @email)
@sess = MockSession.new

# ConcealSecret param contract

## Flat V1 params passed directly — logic reads secret value from 'secret' key
flat_params = {
  'secret' => 'hello world',
  'ttl'    => '3600',
}
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, flat_params, 'en')
logic.secret_value
#=> 'hello world'

## TTL is parsed from the flat params and coerced to integer
flat_params = {
  'secret' => 'ttl test',
  'ttl'    => '3600',
}
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, flat_params, 'en')
logic.ttl
#=> 3600

## Passphrase is read directly from flat params
flat_params = {
  'secret'     => 'pw test',
  'passphrase' => 'hunter2',
}
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, flat_params, 'en')
logic.passphrase
#=> 'hunter2'

## Missing params hash produces empty payload (no crash)
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, {}, 'en')
logic.secret_value
#=> nil

## Kind is set to :conceal by ConcealSecret#process_secret
flat_params = {'secret' => 'kind test'}
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, flat_params, 'en')
logic.kind
#=> :conceal

## raise_concerns raises FormError when secret value is empty
flat_params = {'secret' => ''}
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, flat_params, 'en')
begin
  logic.raise_concerns
rescue Onetime::FormError => e
  e.message
end
#=> "You did not provide anything to share"

## raise_concerns raises FormError when params is empty
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @cust, {}, 'en')
begin
  logic.raise_concerns
rescue Onetime::FormError => e
  e.message
end
#=> "You did not provide anything to share"

# Teardown
@cust.destroy!
