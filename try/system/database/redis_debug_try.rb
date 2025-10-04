# try/80_database/10_redis_debug_try.rb

require_relative '../../support/test_helpers'
require_relative '../../lib/onetime/redis_key_migrator'

OT.boot! :test, true

# Setup section - get Redis config from OT.conf
redis_uri = URI.parse(OT.conf['redis']['uri'])
@redis_host = redis_uri.host
@redis_port = redis_uri.port
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
#=> :copy

## Test key discovery (simple)
discovered_keys = @migrator.send(:discover_keys, 'nonexistent:*')
discovered_keys.class.name
#=> "Array"
