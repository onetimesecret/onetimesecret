# try/80_database/10_redis_key_migrator_basic_try.rb

require_relative '../../support/test_helpers'
require_relative '../../lib/onetime/redis_key_migrator'

OT.boot! :test, true

# Setup section - get Redis config from OT.conf
redis_uri = URI.parse(OT.conf['redis']['uri'])
@@redis_host = redis_uri.host
@@redis_port = redis_uri.port

## Test basic initialization
source_uri = "redis://#{@redis_host}:#{@redis_port}/14"
target_uri = "redis://#{@redis_host}:#{@redis_port}/15"

migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
migrator.class.name
#=> "Onetime::RedisKeyMigrator"

## Test URI parsing database
source_uri = "redis://#{@redis_host}:#{@redis_port}/14"
target_uri = "redis://#{@redis_host}:#{@redis_port}/15"
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
migrator.source_uri.path
#=> "/14"

## Test strategy detection
source_uri = "redis://#{@redis_host}:#{@redis_port}/14"
target_uri = "redis://#{@redis_host}:#{@redis_port}/15"
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
strategy = migrator.send(:determine_migration_strategy)
strategy
#=> :copy
