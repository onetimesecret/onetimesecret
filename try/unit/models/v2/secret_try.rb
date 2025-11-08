# try/21_secret_try.rb
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
# 5. Managing secret states (viewed, received)
#
# These tests aim to ensure that secrets can be correctly created,
# stored, and managed throughout their lifecycle in the application.

require 'set'

require_relative '../../../support/test_models'


@iterations = 1000
OT.boot! :test, true

## Can create Secret
s = Onetime::Secret.new :private
[s.class, s.dbclient.connection[:db], s.metadata_identifier]
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
@metadata, @secret = Onetime::Secret.spawn_pair 'anon', :tryouts
[@metadata.nil?, @secret.nil?]
#=> [false, false]

## Private metadata key matches
p [@secret.metadata_identifier, @metadata.identifier]
[@secret.metadata_identifier.nil?, @secret.metadata_identifier == @metadata.identifier]
#=> [false, true]

## Shared secret key matches
p [@secret.identifier, @metadata.secret_identifier]
[@metadata.secret_identifier.nil?, @metadata.secret_identifier == @secret.identifier]
#=> [false, true]

## Kinds are correct
[@metadata.class, @secret.class]
#=> [Onetime::Metadata, Onetime::Secret]

## Can save a secret and check existence
metadata, secret = Onetime::Secret.spawn_pair 'anon', :tryouts
[metadata.save, metadata.exists?]
#=> [true, true]

## A secret can be destroyed using Familia's destroy! method
metadata, secret = Onetime::Secret.spawn_pair 'anon', :tryouts
metadata.save
metadata.destroy!
!metadata.exists?
#=> true

## Can set private secret to viewed state
metadata, secret = Onetime::Secret.spawn_pair 'anon', :tryouts
metadata.viewed!
[metadata.viewed, metadata.state]
#=> [Familia.now.to_i, 'viewed']

## Can set shared secret to viewed state
metadata, secret = Onetime::Secret.spawn_pair 'anon', :tryouts
metadata.save && secret.save
secret.received!
# NOTE: The secret no longer keeps a reference to the metadata
#metadata = secret.load_metadata
[metadata.shared, metadata.state, secret.received, secret.state]
##=> [Familia.now.to_i, 'shared', Familia.now.to_i, 'received']

## Secrets have a counter for views
@secret_with_counter = Onetime::Secret.new state: :shared
@secret_with_counter.view_count.to_i
#=> 0

## Secrets can keep a view count (1 of 2)
@secret_with_counter.view_count.incr
#=> 1

## Secrets can keep a view count (2 of 2)
@secret_with_counter.view_count.incr
#=> 2

## Secrets counters have their own key
@secret_with_counter.view_count.dbkey
#=> Familia.join(:secret, @secret_with_counter.key, :view_count)

## Secrets counters have their own ttl setting
@secret_with_counter.view_count.default_expiration
#=> 1209600.0

## Secrets counters have their own realttl value
@secret_with_counter.view_count.current_expiration
#=> 1209600
