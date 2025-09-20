# try/redis_debug_try.rb

require_relative '../lib/onetime/redis_key_migrator'

# Setup section
@redis_host = 'localhost'
@redis_port = 2121
@test_db_source = 14

def test_uri(db)
  "redis://#{@redis_host}:#{@redis_port}/#{db}"
end

## Test basic migrator creation
source_uri = test_uri(@test_db_source)
target_uri = test_uri(15)

@migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
@migrator.class.name
#=> "Onetime::RedisKeyMigrator"

## Test strategy determination
strategy = @migrator.send(:determine_migration_strategy)
strategy
#=> :migrate

## Test key discovery (simple)
discovered_keys = @migrator.send(:discover_keys, 'nonexistent:*')
discovered_keys.class.name
#=> "Array"
