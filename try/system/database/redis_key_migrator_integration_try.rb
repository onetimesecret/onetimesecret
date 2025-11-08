# try/80_database/30_redis_key_migrator_integration_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/redis_key_migrator'

OT.boot! :test, true

# Setup section - get Redis config from OT.conf
redis_uri = URI.parse(OT.conf['redis']['uri'])
@redis_host = redis_uri.host
@redis_port = redis_uri.port
@test_db_source = 14
@test_db_target = 15

def test_uri(db)
  "redis://#{@redis_host}:#{@redis_port}/#{db}"
end

def test_client(db)
  Redis.new(host: @redis_host, port: @redis_port, db: db)
end

def setup_test_data
  source_client = test_client(@test_db_source)
  target_client = test_client(@test_db_target)

  # Clear both databases
  source_client.flushdb
  target_client.flushdb

  # Add test data to source
  source_client.set('customer:1', 'test_value_1')
  source_client.set('customer:2', 'test_value_2')
  source_client.setex('customer:temp', 30, 'expires_in_30s')
  source_client.hset('customer:hash:1', 'field1', 'value1')
  source_client.lpush('customer:list:1', 'item1')
  source_client.lpush('customer:list:1', 'item2')
  source_client.sadd('customer:set:1', 'member1')
  source_client.sadd('customer:set:1', 'member2')

  # Add some non-matching keys
  source_client.set('session:1', 'session_data')
  source_client.set('secret:1', 'secret_data')

  source_client.disconnect!
  target_client.disconnect!
end

def cleanup_test_data
  source_client = test_client(@test_db_source)
  target_client = test_client(@test_db_target)
  source_client.flushdb
  target_client.flushdb
  source_client.disconnect!
  target_client.disconnect!
end

## Test same-instance migration strategy detection
source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)

migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
strategy = migrator.send(:determine_migration_strategy)
strategy
#=> :copy

## Test cross-server migration strategy detection
source_uri = "redis://#{@redis_host}:#{@redis_port}/#{@test_db_source}"
target_uri = "redis://otherhost:#{@redis_port}/#{@test_db_target}"

migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
strategy = migrator.send(:determine_migration_strategy)
strategy
#=> :dump_restore

## Test key discovery with pattern
setup_test_data

source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

discovered_keys = migrator.send(:discover_keys, 'customer:*')
discovered_keys.sort
#=> ["customer:1", "customer:2", "customer:hash:1", "customer:list:1", "customer:set:1", "customer:temp"]

## Test key discovery with non-matching pattern
setup_test_data

source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

discovered_keys = migrator.send(:discover_keys, 'nonexistent:*')
discovered_keys
#=> []

## Test migration statistics initialization
source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

stats = migrator.statistics
[stats[:total_keys], stats[:migrated_keys], stats[:failed_keys]]
#=> [0, 0, 0]

## Test CLI command generation for same instance
source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

commands = migrator.generate_cli_commands('customer:*')
[commands[:strategy], commands.keys.sort]
#=> [:copy, [:cleanup, :discovery, :migration, :strategy, :verification]]

## Test CLI command generation for cross-server
source_uri = "redis://#{@redis_host}:#{@redis_port}/#{@test_db_source}"
target_uri = "redis://otherhost:#{@redis_port}/#{@test_db_target}"
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

commands = migrator.generate_cli_commands('customer:*')
commands[:strategy]
#=> :dump_restore

## Test error handling for nil source URI
begin
  migrator = Onetime::RedisKeyMigrator.new(nil, test_uri(@test_db_target))
  migrator.migrate_keys('test:*')
  false
rescue ArgumentError => e
  e.message.include?("Source URI cannot be nil")
end
#=> true

## Test error handling for identical source and target
begin
  same_uri = test_uri(@test_db_source)
  migrator = Onetime::RedisKeyMigrator.new(same_uri, same_uri)
  migrator.migrate_keys('test:*')
  false
rescue ArgumentError => e
  e.message.include?("Source and target cannot be identical")
end
#=> true

## Test empty key set migration
cleanup_test_data

source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

stats = migrator.migrate_keys('nonexistent:*')
[stats[:total_keys], stats[:migrated_keys], stats[:failed_keys]]
#=> [0, 0, 0]

## Test basic same-instance migration
setup_test_data

source_client = test_client(@test_db_source)
target_client = test_client(@test_db_target)

# Verify initial state
source_keys = source_client.keys('customer:*').sort
target_keys = target_client.keys('customer:*')

source_client.disconnect!
target_client.disconnect!

source_uri = test_uri(@test_db_source)
target_uri = test_uri(@test_db_target)
migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)

stats = migrator.migrate_keys('customer:*')

# Verify final state
source_client = test_client(@test_db_source)
target_client = test_client(@test_db_target)

post_source_keys = source_client.keys('customer:*').sort
post_target_keys = target_client.keys('customer:*').sort

source_client.disconnect!
target_client.disconnect!

# Results: [initial_source_count, initial_target_count, final_source_count, final_target_count, strategy]
[source_keys.size, target_keys.size, post_source_keys.size, post_target_keys.size, stats[:strategy_used]]
#=> [6, 0, 6, 6, :copy]

## Test database number extraction
source_uri = test_uri(@test_db_source)
migrator = Onetime::RedisKeyMigrator.new(source_uri, test_uri(@test_db_target))

# Pass the parsed URI, not the string
extracted_db = migrator.send(:extract_db_number, migrator.source_uri)
extracted_db
#=> 14

## Cleanup all test data
cleanup_test_data
true
