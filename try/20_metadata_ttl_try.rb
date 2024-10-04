# frozen_string_literal: true

# These tryouts test the OT::App::API.metadata_hsh method functionality.
# The metadata_hsh method is responsible for transforming metadata
# into a structured hash with enhanced information.
#
# We're testing various aspects of the metadata_hsh method, including:
# 1. Basic metadata transformation
# 2. TTL handling (metadata_ttl, secret_ttl, and real TTL values)
# 3. State-dependent field presence
# 4. Optional parameter handling
#
# These tests aim to ensure that the metadata_hsh method correctly
# processes metadata objects and produces the expected structured
# hash output for the API response.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

# Setup
@metadata, @secret = Onetime::Secret.spawn_pair 'anon', :tryouts
@metadata.save
@secret.save

## Basic metadata transformation (this doubles as a check for FlexibleHashAccess)
result = OT::App::API.metadata_hsh(@metadata)
p [result[:custid], result[:metadata_key], result[:secret_key]]
p [@metadata.custid, @metadata.key, @metadata.secret_key]
[result[:custid], result[:metadata_key], result[:secret_key]]
#=> [@metadata.custid, @metadata.key, @metadata.secret_key]

## TTL handling - metadata_ttl is set to the real TTL value
result = OT::App::API.metadata_hsh(@metadata)
result[:metadata_ttl].is_a?(Integer) && result[:metadata_ttl] > 0
#=> true

## TTL handling - ttl is set to the static value from redis hash field
@metadata.secret_ttl = 3600
result = OT::App::API.metadata_hsh(@metadata)
p result
result[:ttl]
#=> 3600

## TTL handling - secret_ttl is nil when not provided
result = OT::App::API.metadata_hsh(@metadata)
result[:secret_ttl]
#=> nil

## TTL handling - secret_ttl is set when provided
result = OT::App::API.metadata_hsh(@metadata, secret_ttl: 1800)
result[:secret_ttl]
#=> 1800

## State-dependent field presence - 'new' state
result = OT::App::API.metadata_hsh(@metadata)
[result.key?(:secret_key), result.key?(:secret_ttl), result.key?(:received)]
#=> [true, true, false]

## State-dependent field presence - 'received' state
@metadata.state = 'received'
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
[result.key?(:secret_key), result.key?(:secret_ttl), result.key?(:received)]
#=> [false, false, true]

## Optional parameter handling - value
result = OT::App::API.metadata_hsh(@metadata, value: 'test_value')
result[:value]
#=> 'test_value'

## Optional parameter handling - passphrase_required (true)
result = OT::App::API.metadata_hsh(@metadata, passphrase_required: true)
result[:passphrase_required]
#=> true

## Optional parameter handling - passphrase_required (false)
result = OT::App::API.metadata_hsh(@metadata, passphrase_required: false)
result[:passphrase_required]
#=> false

## Handling nil custid
@metadata.custid = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:custid]
#=> ""

## Handling nil secret_key
@metadata.secret_key = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:secret_key]
#=> nil

## Handling nil state
@metadata.state = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:state]
#=> ''

## Handling nil updated timestamp, is overridden when saved
@metadata.updated = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:created].positive?
#=> true

## Handling nil created timestamp, is overridden when saved
@metadata.created = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:created].positive?
#=> true

## Handling nil received timestamp
@metadata.received = nil
@metadata.state = 'received'
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:received]
#=> 0

## Handling nil recipients
@metadata.recipients = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:recipient]
#=> []

## Handling nil secret_ttl in metadata
@metadata.secret_ttl = nil
@metadata.save
result = OT::App::API.metadata_hsh(@metadata)
result[:ttl]
#=> nil

## Handling nil realttl
class Onetime::Metadata
  def realttl; nil; end
end
result = OT::App::API.metadata_hsh(@metadata)
result[:metadata_ttl]
#=> nil

## Handling nil secret_ttl option
result = OT::App::API.metadata_hsh(@metadata, secret_ttl: nil)
result[:secret_ttl]
#=> nil

## Handling nil value option
result = OT::App::API.metadata_hsh(@metadata, value: nil)
result.key?(:value)
#=> false

## Handling nil passphrase_required option
result = OT::App::API.metadata_hsh(@metadata, passphrase_required: nil)
result.key?(:passphrase_required)
#=> false


# Teardown
@metadata.destroy!
@secret.destroy!
