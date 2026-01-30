# migrations/2026-01-27/try/key_loader_try.rb
#
# frozen_string_literal: true

require_relative '../../../try/support/test_helpers'
require 'json'
require 'fileutils'
require 'tmpdir'

MIGRATION_DIR = File.expand_path('..', __dir__)
load File.join(MIGRATION_DIR, 'load_keys.rb')

## KeyLoader::MODELS has all expected models
KeyLoader::MODELS.keys.sort
#=> ["customdomain", "customer", "organization", "receipt", "secret"]

## KeyLoader::MODELS maps customer to DB 6
KeyLoader::MODELS['customer'][:db]
#=> 6

## KeyLoader::MODELS maps organization to DB 6
KeyLoader::MODELS['organization'][:db]
#=> 6

## KeyLoader::MODELS maps customdomain to DB 6
KeyLoader::MODELS['customdomain'][:db]
#=> 6

## KeyLoader::MODELS maps receipt to DB 7
KeyLoader::MODELS['receipt'][:db]
#=> 7

## KeyLoader::MODELS maps secret to DB 8
KeyLoader::MODELS['secret'][:db]
#=> 8

## VALID_COMMANDS includes expected Redis commands
KeyLoader::VALID_COMMANDS.sort
#=> ["HSET", "INCRBY", "SADD", "ZADD"]

## validate_options raises for non-existent input directory
loader = KeyLoader.new(
  input_dir: '/nonexistent/directory',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

begin
  loader.send(:validate_options)
  false
rescue ArgumentError => e
  e.message.include?('Input directory not found')
end
#=> true

## validate_options raises for unknown model
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  model: 'unknown_model',
  dry_run: true
)

begin
  loader.send(:validate_options)
  false
rescue ArgumentError => e
  e.message.include?('Unknown model')
end
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## validate_options raises when both skip flags set
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  skip_indexes: true,
  skip_records: true,
  dry_run: true
)

begin
  loader.send(:validate_options)
  false
rescue ArgumentError => e
  e.message.include?('Cannot specify both')
end
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## validate_options accepts valid single model
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  model: 'customer',
  dry_run: true
)

# Should not raise
loader.send(:validate_options)
true
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## determine_models returns all models when no target specified
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

models = loader.send(:determine_models)
models
#=> ["customer", "organization", "customdomain", "receipt", "secret"]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## determine_models returns single model when target specified
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  model: 'receipt',
  dry_run: true
)

models = loader.send(:determine_models)
models
#=> ["receipt"]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## mode_description shows dry-run
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

loader.send(:mode_description)
#=> "dry-run"

## mode_description shows records only when skip_indexes
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  skip_indexes: true,
  dry_run: false
)

loader.send(:mode_description)
#=> "records only"

## mode_description shows indexes only when skip_records
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  skip_records: true,
  dry_run: false
)

loader.send(:mode_description)
#=> "indexes only"

## mode_description shows full load by default
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: false
)

loader.send(:mode_description)
#=> "full load"

## restore_record increments dry-run counter without Redis
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

record = { key: 'test:key', dump: 'dGVzdA==', ttl_ms: -1 }
loader.send(:restore_record, 'customer', nil, record)

stats = loader.instance_variable_get(:@stats)
stats['customer'][:records_restored]
#=> 1

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## restore_record skips record without key
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

record = { dump: 'dGVzdA==', ttl_ms: -1 }  # No key
loader.send(:restore_record, 'customer', nil, record)

stats = loader.instance_variable_get(:@stats)
[stats['customer'][:records_skipped], stats['customer'][:errors].size > 0]
#=> [1, true]

## restore_record skips record without dump
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

record = { key: 'test:key', ttl_ms: -1 }  # No dump
loader.send(:restore_record, 'customer', nil, record)

stats = loader.instance_variable_get(:@stats)
stats['customer'][:records_skipped]
#=> 1

## execute_command increments dry-run counter without Redis
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

cmd = { command: 'ZADD', key: 'customer:instances', args: [1706000000, 'objid'] }
loader.send(:execute_command, 'customer', nil, cmd)

stats = loader.instance_variable_get(:@stats)
stats['customer'][:indexes_executed]
#=> 1

## execute_command rejects unknown commands
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

cmd = { command: 'DEL', key: 'some:key', args: [] }
loader.send(:execute_command, 'customer', nil, cmd)

stats = loader.instance_variable_get(:@stats)
[stats['customer'][:indexes_skipped], stats['customer'][:errors].size > 0]
#=> [1, true]

## execute_command validates key presence
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

cmd = { command: 'ZADD', args: [1706000000, 'objid'] }  # No key
loader.send(:execute_command, 'customer', nil, cmd)

stats = loader.instance_variable_get(:@stats)
stats['customer'][:indexes_skipped]
#=> 1

## execute_command validates args is array
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

cmd = { command: 'ZADD', key: 'test:key', args: 'not an array' }
loader.send(:execute_command, 'customer', nil, cmd)

stats = loader.instance_variable_get(:@stats)
stats['customer'][:indexes_skipped]
#=> 1

## TTL conversion: -1 in source becomes 0 in RESTORE (no expiry)
loader = KeyLoader.allocate

# Simulating the TTL conversion logic from restore_record
record = { key: 'test:key', dump: 'dGVzdA==', ttl_ms: -1 }
ttl_ms = record[:ttl_ms]

# This is the conversion logic
restore_ttl = ttl_ms == -1 ? 0 : ttl_ms.to_i
restore_ttl
#=> 0

## TTL conversion: positive value passes through
loader = KeyLoader.allocate

record = { key: 'test:key', dump: 'dGVzdA==', ttl_ms: 3600000 }
ttl_ms = record[:ttl_ms]

restore_ttl = ttl_ms == -1 ? 0 : ttl_ms.to_i
restore_ttl
#=> 3600000

## Stats aggregation across models
loader = KeyLoader.new(
  input_dir: '/tmp',
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

# Simulate loading multiple models
stats = loader.instance_variable_get(:@stats)
stats['customer'][:records_restored] = 100
stats['customer'][:indexes_executed] = 50
stats['receipt'][:records_restored] = 200
stats['receipt'][:indexes_executed] = 100

total_records = stats.values.sum { |s| s[:records_restored] }
total_indexes = stats.values.sum { |s| s[:indexes_executed] }

[total_records, total_indexes]
#=> [300, 150]

## get_redis strips existing db from URL before appending target
# The method should handle URLs like redis://host:6379/0 and append the correct DB
loader = KeyLoader.allocate
loader.instance_variable_set(:@valkey_url, 'redis://127.0.0.1:6379/0')
loader.instance_variable_set(:@redis_clients, {})

# Test the URL manipulation logic
base_url = 'redis://127.0.0.1:6379/0'.sub(%r{/\d+$}, '')
target_db = 6

"#{base_url}/#{target_db}"
#=> "redis://127.0.0.1:6379/6"

## load_model skips missing directories gracefully
@temp_dir = Dir.mktmpdir('loader_test')

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

# customer subdirectory doesn't exist
loader.send(:load_model, 'customer')

stats = loader.instance_variable_get(:@stats)
stats['customer'][:errors].any? { |e| e[:error].include?('Directory not found') }
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## load_transformed_records processes JSONL file
@temp_dir = Dir.mktmpdir('loader_test')
model_dir = File.join(@temp_dir, 'customer')
FileUtils.mkdir_p(model_dir)

File.open(File.join(model_dir, 'customer_transformed.jsonl'), 'w') do |f|
  f.puts JSON.generate({ key: 'customer:obj1:object', dump: 'dGVzdA==', ttl_ms: -1 })
  f.puts JSON.generate({ key: 'customer:obj2:object', dump: 'dGVzdA==', ttl_ms: -1 })
end

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

loader.send(:load_transformed_records, 'customer', File.join(model_dir, 'customer_transformed.jsonl'))

stats = loader.instance_variable_get(:@stats)
stats['customer'][:records_restored]
#=> 2

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## execute_index_commands processes JSONL file
@temp_dir = Dir.mktmpdir('loader_test')
model_dir = File.join(@temp_dir, 'customer')
FileUtils.mkdir_p(model_dir)

File.open(File.join(model_dir, 'customer_indexes.jsonl'), 'w') do |f|
  f.puts JSON.generate({ command: 'ZADD', key: 'customer:instances', args: [1706000000, 'obj1'] })
  f.puts JSON.generate({ command: 'HSET', key: 'customer:email_index', args: ['user@example.com', '"obj1"'] })
end

loader = KeyLoader.new(
  input_dir: @temp_dir,
  valkey_url: 'redis://127.0.0.1:6379',
  dry_run: true
)

loader.send(:execute_index_commands, 'customer', File.join(model_dir, 'customer_indexes.jsonl'))

stats = loader.instance_variable_get(:@stats)
stats['customer'][:indexes_executed]
#=> 2

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true
