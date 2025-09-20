# try/80_database/10_redis_key_migrator_basic_try.rb

require_relative '../lib/onetime/redis_key_migrator'

## Test basic initialization
source_uri = "redis://localhost:2121/14"
target_uri = "redis://localhost:2121/15"

migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
migrator.class.name
#=> "Onetime::RedisKeyMigrator"

## Test URI parsing
source_uri = "redis://localhost:2121/14"
target_uri = "redis://localhost:2121/15"
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
migrator.source_uri.host
#=> "localhost"

## Test URI parsing database
source_uri = "redis://localhost:2121/14"
target_uri = "redis://localhost:2121/15"
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
migrator.source_uri.path
#=> "/14"

## Test strategy detection
source_uri = "redis://localhost:2121/14"
target_uri = "redis://localhost:2121/15"
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
strategy = migrator.send(:determine_migration_strategy)
strategy
#=> :migrate
