# try/features/incoming/incoming_config_try.rb
#
# frozen_string_literal: true

# These tryouts test the incoming secrets configuration and recipient handling.
# They verify:
# 1. Feature configuration loading from config
# 2. Recipient lookup via hash
# 3. Public recipients list generation (without email exposure)

require_relative '../../support/test_models'
OT.boot! :test, false

# Test recipient configuration from DEFAULTS
# Note: In actual deployment, recipients would be configured in config.yaml

## Incoming feature is disabled by default
config = OT.conf.dig('features', 'incoming')
config['enabled']
#=> false

## Default memo max length is 50
config = OT.conf.dig('features', 'incoming')
config['memo_max_length']
#=> 50

## Default TTL is 7 days (604800 seconds)
config = OT.conf.dig('features', 'incoming')
config['default_ttl']
#=> 604_800

## Default recipients list is empty
config = OT.conf.dig('features', 'incoming')
config['recipients']
#=> []

## Public recipients list is empty by default (no initializer run)
OT.incoming_public_recipients
#=> []

## Recipient lookup returns nil for unknown hash
OT.lookup_incoming_recipient('unknown_hash_123')
#=> nil

## Can access memo field on Metadata model
metadata = Onetime::Metadata.new
metadata.memo = 'Test memo'
metadata.memo
#=> 'Test memo'
