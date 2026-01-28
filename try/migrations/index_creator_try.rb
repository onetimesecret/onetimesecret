# try/migrations/index_creator_try.rb
#
# Unit tests for index creation scripts.
# Tests customer, organization, and customdomain index generation.
#
# frozen_string_literal: true

require_relative '../support/test_helpers'
require 'json'
require 'fileutils'
require 'tmpdir'

MIGRATION_DIR = File.expand_path('../../migrations/2026-01-26', __dir__)
load File.join(MIGRATION_DIR, '01-customer', 'create_indexes.rb')

## CustomerIndexCreator has correct TEMP_KEY_PREFIX
CustomerIndexCreator::TEMP_KEY_PREFIX
#=> "_migrate_tmp_"

## COUNTER_FIELDS includes all expected counters
expected_counters = %w[secrets_created secrets_shared secrets_burned emails_sent]
CustomerIndexCreator::COUNTER_FIELDS
#=> ["secrets_created", "secrets_shared", "secrets_burned", "emails_sent"]

## VALID_ROLES includes expected role values
CustomerIndexCreator::VALID_ROLES
#=> ["colonel", "customer", "anonymous"]

## Stats initialization includes all tracking fields
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
expected_keys = %i[records_read objects_processed instance_index_source instance_entries
                   email_lookups extid_lookups objid_lookups role_entries counters skipped errors]
expected_keys.all? { |k| stats.key?(k) }
#=> true

## resolve_identifiers prefers JSONL objid/extid
creator = CustomerIndexCreator.allocate

objid, extid = creator.send(:resolve_identifiers, 'jsonl-objid', 'jsonl-extid', {
  'objid' => 'hash-objid',
  'extid' => 'hash-extid'
})

[objid, extid]
#=> ["jsonl-objid", "jsonl-extid"]

## resolve_identifiers falls back to hash fields
creator = CustomerIndexCreator.allocate

objid, extid = creator.send(:resolve_identifiers, nil, nil, {
  'objid' => 'hash-objid',
  'extid' => 'hash-extid'
})

[objid, extid]
#=> ["hash-objid", "hash-extid"]

## resolve_identifiers uses custid as final fallback for objid
creator = CustomerIndexCreator.allocate

objid, extid = creator.send(:resolve_identifiers, nil, nil, {
  'custid' => 'user@example.com'
})

# extid is nil since not provided
[objid, extid]
#=> ["user@example.com", nil]

## accumulate_counters aggregates values correctly
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

fields1 = { 'secrets_created' => '10', 'secrets_shared' => '5' }
fields2 = { 'secrets_created' => '20', 'emails_sent' => '3' }

creator.send(:accumulate_counters, fields1)
creator.send(:accumulate_counters, fields2)

stats = creator.instance_variable_get(:@stats)
[stats[:counters]['secrets_created'], stats[:counters]['secrets_shared'], stats[:counters]['emails_sent']]
#=> [30, 5, 3]

## accumulate_counters ignores zero and negative values
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

fields = { 'secrets_created' => '0', 'secrets_shared' => '-1', 'secrets_burned' => '5' }
creator.send(:accumulate_counters, fields)

stats = creator.instance_variable_get(:@stats)
[stats[:counters]['secrets_created'], stats[:counters]['secrets_shared'], stats[:counters]['secrets_burned']]
#=> [0, 0, 5]

## generate_counter_commands creates INCRBY commands
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:counters]['secrets_created'] = 100
stats[:counters]['emails_sent'] = 50

commands = creator.send(:generate_counter_commands)

# Should have 2 INCRBY commands
commands.size
#=> 2

## generate_counter_commands format is correct
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:counters]['secrets_created'] = 100

commands = creator.send(:generate_counter_commands)
cmd = commands.find { |c| c[:key] == 'customer:secrets_created' }

[cmd[:command], cmd[:args]]
#=> ["INCRBY", ["100"]]

## generate_counter_commands skips zero-value counters
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
# Leave all counters at 0

commands = creator.send(:generate_counter_commands)
commands.size
#=> 0

## build_customer_index_commands creates email lookup
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

# Set instance_index_source to skip instance entry generation
stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = { 'email' => 'user@example.com', 'role' => 'customer' }
objid = 'cust-objid-123'
extid = 'urextid0000000000000000000'

creator.send(:build_customer_index_commands, commands, record, fields, objid, extid)

email_cmd = commands.find { |c| c[:key] == 'customer:email_index' }
[email_cmd[:command], email_cmd[:args][0], email_cmd[:args][1]]
#=> ["HSET", "user@example.com", "\"cust-objid-123\""]

## email lookup value is JSON-encoded for Familia compatibility
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = { 'email' => 'test@example.com' }
objid = 'test-objid'

creator.send(:build_customer_index_commands, commands, record, fields, objid, nil)

email_cmd = commands.find { |c| c[:key] == 'customer:email_index' }

# Value should be JSON-encoded (wrapped in quotes)
JSON.parse(email_cmd[:args][1])
#=> "test-objid"

## build_customer_index_commands creates extid lookup when present
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = {}
objid = 'cust-objid'
extid = 'urextid0000000000000000000'

creator.send(:build_customer_index_commands, commands, record, fields, objid, extid)

extid_cmd = commands.find { |c| c[:key] == 'customer:extid_lookup' }
[extid_cmd[:command], extid_cmd[:args][0]]
#=> ["HSET", "urextid0000000000000000000"]

## build_customer_index_commands skips extid lookup when nil
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = {}
objid = 'cust-objid'
extid = nil  # No extid

creator.send(:build_customer_index_commands, commands, record, fields, objid, extid)

extid_cmd = commands.find { |c| c[:key] == 'customer:extid_lookup' }
extid_cmd
#=> nil

## build_customer_index_commands creates objid lookup
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = {}
objid = 'cust-objid-123'

creator.send(:build_customer_index_commands, commands, record, fields, objid, nil)

objid_cmd = commands.find { |c| c[:key] == 'customer:objid_lookup' }
[objid_cmd[:command], objid_cmd[:args][0]]
#=> ["HSET", "cust-objid-123"]

## build_customer_index_commands creates role index for valid roles
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = { 'role' => 'colonel' }
objid = 'cust-objid'

creator.send(:build_customer_index_commands, commands, record, fields, objid, nil)

role_cmd = commands.find { |c| c[:key] == 'customer:role_index:colonel' }
[role_cmd[:command], role_cmd[:args]]
#=> ["SADD", ["cust-objid"]]

## build_customer_index_commands skips role index for invalid roles
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'

commands = []
record = { created: 1706000000 }
fields = { 'role' => 'invalid_role' }
objid = 'cust-objid'

creator.send(:build_customer_index_commands, commands, record, fields, objid, nil)

role_cmd = commands.find { |c| c[:key].start_with?('customer:role_index:') }
role_cmd
#=> nil

## build_customer_index_commands creates instance entry when no existing index
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'generated'  # No existing v1 index

commands = []
record = { created: 1706000000 }
fields = {}
objid = 'cust-objid'

creator.send(:build_customer_index_commands, commands, record, fields, objid, nil)

instance_cmd = commands.find { |c| c[:key] == 'customer:instances' }
[instance_cmd[:command], instance_cmd[:args]]
#=> ["ZADD", [1706000000, "cust-objid"]]

## build_customer_index_commands skips instance entry when existing index
creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = creator.instance_variable_get(:@stats)
stats[:instance_index_source] = 'existing'  # Using v1 index

commands = []
record = { created: 1706000000 }
fields = {}
objid = 'cust-objid'

creator.send(:build_customer_index_commands, commands, record, fields, objid, nil)

instance_cmd = commands.find { |c| c[:key] == 'customer:instances' }
instance_cmd
#=> nil

## write_output creates both indexes and lookup files
@temp_dir = Dir.mktmpdir('index_test')

creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

# Manually set the email_to_objid mapping
creator.instance_variable_set(:@email_to_objid, { 'user@example.com' => 'objid-123' })

commands = [{ command: 'HSET', key: 'customer:email_index', args: ['user@example.com', '"objid-123"'] }]
creator.send(:write_output, commands)

[
  File.exist?(File.join(@temp_dir, 'customer_indexes.jsonl')),
  File.exist?(File.join(@temp_dir, 'email_to_objid.json'))
]
#=> [true, true]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## email_to_objid.json contains valid JSON mapping
@temp_dir = Dir.mktmpdir('index_test')

creator = CustomerIndexCreator.new(
  input_file: '/tmp/test.jsonl',
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

creator.instance_variable_set(:@email_to_objid, {
  'user1@example.com' => 'objid-1',
  'user2@example.com' => 'objid-2'
})

creator.send(:write_output, [])

lookup = JSON.parse(File.read(File.join(@temp_dir, 'email_to_objid.json')))
lookup
#=> {"user1@example.com"=>"objid-1", "user2@example.com"=>"objid-2"}

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true
