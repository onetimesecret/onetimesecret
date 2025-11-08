# try/unit/models/v2/metadata_try.rb
#
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

require 'securerandom'

require_relative '../../../support/test_models'

#Familia.debug = true

OT.boot! :test, true

@iterations = 1000

## Can create a Metadata
m = Onetime::Metadata.new :private
[m.class, m.dbclient.connection[:db], m.secret_identifier]
#=> [Onetime::Metadata, 0, nil]

## Can explicitly set the secret key
m = Onetime::Metadata.new :private
m.secret_identifier = 'hihi'
[m.class, m.dbclient.connection[:db], m.secret_identifier]
#=> [Onetime::Metadata, 0, 'hihi']

## Keys are always unique for Metadata
## NOTE: Prior to Familia v1.0.0.pre.rc1 upgrade the metadata key
## here was `ivfn09cpriklqii1zagw6fc96suh8bp` (1 of 2)
unique_values = Set.new
@iterations.times do
  s = Onetime::Metadata.new state: :metadata
  unique_values.add(s.dbkey)
end
unique_values.size
#=> @iterations

## And are not affected (or effected) by arguments
## NOTE: Prior to Familia v1.0.0.pre.rc1 upgrade the metadata key
## here was `ivfn09cpriklqii1zagw6fc96suh8bp` (2 of 2)
unique_values = Set.new
@iterations.times do
  s = Onetime::Metadata.new state: %i[some fixed values]
  unique_values.add(s.dbkey)
end
unique_values.size
#=> @iterations

## Doesn't exist yet
@metadata = Onetime::Metadata.new :metadata, [OT.instance, Familia.now.to_f, SecureRandom.hex]
@metadata.exists?
#=> false

## Does exist
@metadata.save
p @metadata.to_h # from ruby memory to hash
p @metadata.hgetall # from db memory to hash
@metadata.exists?
#=> true

@metadata.destroy!
