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

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot!

## Keys are consistent for Metadata
@metadata = Onetime::Metadata.new :metadata, :entropy
[@metadata.rediskey, @metadata.db, @metadata.secret_key, @metadata.all]
#=> ['metadata:ivfn09cpriklqii1zagw6fc96suh8bp:object', 7, nil, {}]

## Keys don't change with values
@metadata.secret_key = "hihi"
[@metadata.rediskey, @metadata.secret_key, @metadata.all]
#=> ['metadata:ivfn09cpriklqii1zagw6fc96suh8bp:object', "hihi", {"secret_key"=>"hihi"}]

## Doesn't exist yet
@metadata2 = Onetime::Metadata.new :metadata, [OT.instance, Time.now.to_f, OT.entropy]
@metadata2.exists?
#=> false

## Does exist
@metadata2.save
p @metadata2.all
@metadata2.exists?
#=> true

@metadata.destroy!
@metadata2.destroy!
