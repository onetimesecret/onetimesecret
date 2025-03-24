# tests/unit/ruby/try/21_secret_try.rb

# These tryouts test the V2::Secret class functionality.
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

require_relative './test_helpers'
require 'onetime/models'

# Use the default config file for tests
@iterations = 1000
OT.boot! :test, true

## Can create Secret
s = V2::Secret.new :private
[s.class, s.redis.connection[:db], s.metadata_key]
#=> [V2::Secret, 8, nil]

## Keys are always unique for Secrets
unique_values = Set.new
@iterations.times do
  s = V2::Secret.new state: :shared
  unique_values.add(s.rediskey)
end
unique_values.size
#=> @iterations

## And are not effected (or affected) by arguments
unique_values = Set.new
@iterations.times do
  s = V2::Secret.new state: %i[some fixed values]
  unique_values.add(s.rediskey)
end
unique_values.size
#=> @iterations

## Generate a pair
@metadata, @secret = V2::Secret.spawn_pair 'anon', :tryouts
[@metadata.nil?, @secret.nil?]
#=> [false, false]

## Private metadata key matches
p [@secret.metadata_key, @metadata.key]
[@secret.metadata_key.nil?, @secret.metadata_key == @metadata.key]
#=> [false, true]

## Shared secret key matches
p [@secret.key, @metadata.secret_key]
[@metadata.secret_key.nil?, @metadata.secret_key == @secret.key]
#=> [false, true]

## Kinds are correct
[@metadata.class, @secret.class]
#=> [V2::Metadata, V2::Secret]

## Can save a secret
@metadata.save
#=> true

## A saved secret exists
@metadata.exists?
#=> true

## A secret can be destroyed
@metadata.destroy!
#=> true

## Can set private secret to viewed state
metadata, secret = V2::Secret.spawn_pair 'anon', :tryouts
metadata.viewed!
[metadata.viewed, metadata.state]
#=> [Time.now.utc.to_i, 'viewed']

## Can set shared secret to viewed state
metadata, secret = V2::Secret.spawn_pair 'anon', :tryouts
metadata.save && secret.save
secret.received!
# NOTE: The secret no longer keeps a reference to the metadata
#metadata = secret.load_metadata
[metadata.shared, metadata.state, secret.received, secret.state]
##=> [Time.now.utc.to_i, 'shared', Time.now.utc.to_i, 'received']

## Secrets have a counter for views
@secret_with_counter = V2::Secret.new state: :shared
@secret_with_counter.view_count.to_i
#=> 0

## Secrets can keep a view count (1 of 2)
@secret_with_counter.view_count.incr
#=> 1

## Secrets can keep a view count (2 of 2)
@secret_with_counter.view_count.incr
#=> 2

## Secrets counters have their own key
@secret_with_counter.view_count.rediskey
#=> Familia.join(:secret, @secret_with_counter.key, :view_count)

## Secrets counters have their own ttl setting
@secret_with_counter.view_count.ttl
#=> 1209600.0

## Secrets counters have their own realttl value
@secret_with_counter.view_count.realttl
#=> 1209600
