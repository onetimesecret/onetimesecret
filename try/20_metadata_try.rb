# frozen_string_literal: true

# These tryouts test the Onetime::Metadata class functionality.
# The Metadata class is responsible for managing metadata associated
# with secrets in the Onetime application.
#
# We're testing various aspects of the Metadata class, including:
# 1. Creation and initialization of Metadata objects
# 2. Consistency of Redis keys and secret keys
# 3. Saving and destroying Metadata objects
# 4. Checking existence of Metadata in the database
#
# These tests aim to ensure that metadata can be correctly created,
# stored, and managed, which is crucial for maintaining information
# about secrets in the application.

require_relative '../lib/onetime'
#Familia.debug = true

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

@iterations = 1000

## Can create a Metadata
m = Onetime::Metadata.new :private
[m.class, m.db, m.secret_key]
#=> [Onetime::Metadata, 7, nil]

## Can explicitly set the secret key
m = Onetime::Metadata.new :private
m.secret_key = 'hihi'
[m.class, m.db, m.secret_key]
#=> [Onetime::Metadata, 7, 'hihi']

## Keys are always unique for Metadata
## NOTE: Prior to Familia v1.0.0.pre.rc1 upgrade the metadata key
## here was `ivfn09cpriklqii1zagw6fc96suh8bp` (1 of 2)
unique_values = Set.new
@iterations.times do
  s = Onetime::Metadata.new state: :metadata
  unique_values.add(s.rediskey)
end
unique_values.size
#=> @iterations

## And are not affected (or effected) by arguments
## NOTE: Prior to Familia v1.0.0.pre.rc1 upgrade the metadata key
## here was `ivfn09cpriklqii1zagw6fc96suh8bp` (2 of 2)
unique_values = Set.new
@iterations.times do
  s = Onetime::Metadata.new state: %i[some fixed values]
  unique_values.add(s.rediskey)
end
unique_values.size
#=> @iterations

## Doesn't exist yet
@metadata = Onetime::Metadata.new :metadata, [OT.instance, Time.now.to_f, OT.entropy]
@metadata.exists?
#=> false

## Does exist
@metadata.save
p @metadata.to_h # from ruby memory to hash
p @metadata.hgetall # from redis memory to hash
@metadata.exists?
#=> true

@metadata.destroy!
