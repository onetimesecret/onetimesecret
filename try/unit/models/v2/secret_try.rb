# try/unit/models/v2/secret_try.rb
#
# frozen_string_literal: true

# These tryouts test the Onetime::Secret class functionality.
# The Secret class is responsible for managing secrets in the
# Onetime application.
#
# We're testing various aspects of the Secret class, including:
# 1. Creation of Secret objects
# 2. Consistency of Redis keys
# 3. Spawning secret pairs (metadata and secret)
# 4. Saving, loading, and destroying secrets
# 5. Managing secret states (previewed, revealed)
#
# These tests aim to ensure that secrets can be correctly created,
# stored, and managed throughout their lifecycle in the application.

require 'set'

require_relative '../../../support/test_models'


@iterations = 1000
OT.boot! :test, true

## Can create Secret
s = Onetime::Secret.new :private
[s.class, s.dbclient.connection[:db], s.receipt_identifier]
#=> [Onetime::Secret, 0, nil]

## Keys are always unique for Secrets
unique_values = Set.new
@iterations.times do
  s = Onetime::Secret.new state: :shared
  unique_values.add(s.dbkey)
end
unique_values.size
#=> @iterations

## And are not effected (or affected) by arguments
unique_values = Set.new
@iterations.times do
  s = Onetime::Secret.new state: %i[some fixed values]
  unique_values.add(s.dbkey)
end
unique_values.size
#=> @iterations

## Generate a pair
@receipt, @secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
[@receipt.nil?, @secret.nil?]
#=> [false, false]

## Receipt key matches
p [@secret.receipt_identifier, @receipt.identifier]
[@secret.receipt_identifier.nil?, @secret.receipt_identifier == @receipt.identifier]
#=> [false, true]

## Shared secret key matches
p [@secret.identifier, @receipt.secret_identifier]
[@receipt.secret_identifier.nil?, @receipt.secret_identifier == @secret.identifier]
#=> [false, true]

## Kinds are correct
[@receipt.class, @secret.class]
#=> [Onetime::Receipt, Onetime::Secret]

## Can save a secret and check existence
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
[receipt.save, receipt.exists?]
#=> [true, true]

## A secret can be destroyed using Familia's destroy! method
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.save
receipt.destroy!
!receipt.exists?
#=> true

## Can set receipt to previewed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
[receipt.previewed, receipt.state]
#=> [Familia.now.to_i, 'previewed']

# NOTE: The received method has been removed from the Secret model.
# The secret no longer keeps a reference to the receipt.

# NOTE: view_count functionality has been removed from Secret model
# These tests are commented out for now
#
## Secrets have a counter for views
#@secret_with_counter = Onetime::Secret.new state: :shared
#@secret_with_counter.view_count.to_i
##=> 0
#
## Secrets can keep a view count (1 of 2)
#@secret_with_counter.view_count.incr
##=> 1
#
## Secrets can keep a view count (2 of 2)
#@secret_with_counter.view_count.incr
##=> 2
#
## Secrets counters have their own key
#@secret_with_counter.view_count.dbkey
##=> Familia.join(:secret, @secret_with_counter.key, :view_count)
#
## Secrets counters have their own ttl setting
#@secret_with_counter.view_count.default_expiration
##=> 1209600.0
#
## Secrets counters have their own realttl value
#@secret_with_counter.view_count.current_expiration
##=> 1209600
