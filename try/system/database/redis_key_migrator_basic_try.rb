# try/system/database/redis_key_migrator_basic_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/services/redis_key_migrator'

OT.boot! :test, true

# Setup section - get Redis config from OT.conf
redis_uri = URI.parse(OT.conf['redis']['uri'])
@@redis_host = redis_uri.host
@@redis_port = redis_uri.port

## basic initialization
source_uri = "redis://#{@redis_host}:#{@redis_port}/14"
target_uri = "redis://#{@redis_host}:#{@redis_port}/15"

migrator = Onetime::Services::RedisKeyMigrator.new(source_uri, target_uri)
migrator.class.name
#=> "Onetime::Services::RedisKeyMigrator"

## URI parsing database
source_uri = "redis://#{@redis_host}:#{@redis_port}/14"
target_uri = "redis://#{@redis_host}:#{@redis_port}/15"
migrator = Onetime::Services::RedisKeyMigrator.new(source_uri, target_uri)
migrator.source_uri.path
#=> "/14"

## strategy detection
source_uri = "redis://#{@redis_host}:#{@redis_port}/14"
target_uri = "redis://#{@redis_host}:#{@redis_port}/15"
migrator = Onetime::Services::RedisKeyMigrator.new(source_uri, target_uri)
strategy = migrator.send(:determine_migration_strategy)
strategy
#=> :copy
