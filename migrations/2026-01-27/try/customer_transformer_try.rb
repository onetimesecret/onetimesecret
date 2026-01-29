# try/migrations/customer_transformer_try.rb
#
# Unit tests for the CustomerTransformer class from 01-customer/transform.rb
# Tests customer data transformation from V1 to V2 format.
#
# These tests use a mock Redis approach for the restore/dump operations
# to avoid requiring a running Redis instance.
#
# frozen_string_literal: true

require_relative '../../../try/support/test_helpers'
require 'json'
require 'base64'
require 'fileutils'
require 'tmpdir'

# Load the transformer class
MIGRATION_DIR = File.expand_path('..', __dir__)
load File.join(MIGRATION_DIR, '01-customer', 'transform.rb')

## CustomerTransformer initializes with correct defaults
transformer = CustomerTransformer.new(
  input_file: 'exports/customer/customer_dump.jsonl',
  output_dir: 'exports/customer',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)
transformer.instance_variable_get(:@dry_run)
#=> true

## TEMP_KEY_PREFIX is set for cleanup identification
CustomerTransformer::TEMP_KEY_PREFIX
#=> "_migrate_tmp_transform_"

## group_records_by_customer extracts custid from key
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

File.open(input_file, 'w') do |f|
  f.puts JSON.generate({ key: 'customer:user1@example.com:object', dump: 'dGVzdA==' })
  f.puts JSON.generate({ key: 'customer:user1@example.com:receipts', dump: 'dGVzdA==' })
  f.puts JSON.generate({ key: 'customer:user2@example.com:object', dump: 'dGVzdA==' })
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

@groups = transformer.send(:group_records_by_customer)
@groups.keys.sort
#=> ["user1@example.com", "user2@example.com"]

## group_records_by_customer groups multiple records per customer
# Continuing from previous test
@groups['user1@example.com'].size
#=> 2

## group_records_by_customer includes only customer-prefixed keys
# Continuing from previous test
@groups['user2@example.com'].size
#=> 1

## Cleanup temp directory
FileUtils.rm_rf(@temp_dir)
true
#=> true

## validate_input_file raises for missing file
transformer = CustomerTransformer.new(
  input_file: '/nonexistent/path/file.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

begin
  transformer.send(:validate_input_file)
  false
rescue ArgumentError => e
  e.message.include?('Input file not found')
end
#=> true

## rename_related_records transforms metadata to receipts
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

records = [
  { key: 'customer:user@example.com:metadata', dump: 'dGVzdA==' },
  { key: 'customer:user@example.com:secrets', dump: 'dGVzdA==' }
]

objid = '0190a0b0-c0d0-7e00-f000-000000000001'
v2_records = transformer.send(:rename_related_records, records, objid)

v2_records.map { |r| r[:key] }
#=> ["customer:0190a0b0-c0d0-7e00-f000-000000000001:receipts", "customer:0190a0b0-c0d0-7e00-f000-000000000001:secrets"]

## rename_related_records preserves original record data
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

records = [
  { key: 'customer:user@example.com:secrets', dump: 'dGVzdA==', ttl_ms: -1, db: 6 }
]

objid = '0190a0b0-c0d0-7e00-f000-000000000001'
v2_records = transformer.send(:rename_related_records, records, objid)

[v2_records[0][:dump], v2_records[0][:ttl_ms], v2_records[0][:db]]
#=> ["dGVzdA==", -1, 6]

## resolve_identifiers prefers JSONL record identifiers
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

record = {
  objid: 'from-jsonl-record',
  extid: 'urfrommjsonlrecord0000000'
}
fields = {
  'objid' => 'from-hash-field',
  'extid' => 'urfromhashfield0000000000'
}

objid, extid = transformer.send(:resolve_identifiers, record, fields)
[objid, extid]
#=> ["from-jsonl-record", "urfrommjsonlrecord0000000"]

## resolve_identifiers falls back to hash fields when JSONL empty
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

record = {}  # No objid/extid in JSONL
fields = {
  'objid' => 'from-hash-field',
  'extid' => 'urfromhashfield0000000000'
}

objid, extid = transformer.send(:resolve_identifiers, record, fields)
[objid, extid]
#=> ["from-hash-field", "urfromhashfield0000000000"]

## Stats initialized with correct structure
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = transformer.instance_variable_get(:@stats)
stats.keys.sort
#=> [:customers_processed, :errors, :renamed_related, :skipped_customers, :transformed_objects, :v1_records_read, :v2_records_written]

## Stats renamed_related is a hash for tracking by type
transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = transformer.instance_variable_get(:@stats)
stats[:renamed_related].class
#=> Hash

## process_customer skips when no :object record found
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

# Create file with only related records, no :object
File.open(input_file, 'w') do |f|
  f.puts JSON.generate({ key: 'customer:user@example.com:receipts', dump: 'dGVzdA==' })
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

records = [{ key: 'customer:user@example.com:receipts', dump: 'dGVzdA==' }]
result = transformer.send(:process_customer, 'user@example.com', records)

stats = transformer.instance_variable_get(:@stats)
[result, stats[:skipped_customers]]
#=> [[], 1]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## Dry-run mode returns empty from process_customer
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

File.open(input_file, 'w') do |f|
  f.puts JSON.generate({
    key: 'customer:user@example.com:object',
    dump: 'dGVzdA==',
    objid: '0190a0b0-c0d0-7e00-f000-000000000001'
  })
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true  # This is the key - dry_run mode
)

records = [{ key: 'customer:user@example.com:object', dump: 'dGVzdA==' }]
result = transformer.send(:process_customer, 'user@example.com', records)

# In dry-run, process_customer returns [] after finding :object record
result
#=> []

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## JSON parse errors during grouping are recorded
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

File.open(input_file, 'w') do |f|
  f.puts 'invalid json {'
  f.puts JSON.generate({ key: 'customer:user@example.com:object', dump: 'dGVzdA==' })
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

groups = transformer.send(:group_records_by_customer)
stats = transformer.instance_variable_get(:@stats)

[groups.keys.size, stats[:errors].size > 0]
#=> [1, true]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## Error messages include line number for JSON parse errors
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

File.open(input_file, 'w') do |f|
  f.puts 'invalid json {'
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

transformer.send(:group_records_by_customer)
stats = transformer.instance_variable_get(:@stats)

stats[:errors].first.key?(:line)
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## write_output creates output file with correct name
@temp_dir = Dir.mktmpdir('customer_test')

transformer = CustomerTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: false
)

records = [
  { key: 'customer:objid1:object', dump: 'dGVzdA==', ttl_ms: -1 },
  { key: 'customer:objid1:receipts', dump: 'dGVzdA==', ttl_ms: -1 }
]

transformer.send(:write_output, records)

File.exist?(File.join(@temp_dir, 'customer_transformed.jsonl'))
#=> true

## write_output writes all records as JSONL
# Continuing from previous test
@output_lines = File.readlines(File.join(@temp_dir, 'customer_transformed.jsonl'))
@output_lines.size
#=> 2

## write_output produces valid JSON per line
# Continuing from previous test
@output_lines.all? { |line| JSON.parse(line) rescue false }
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## Records grouped correctly skip non-customer prefixed keys
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

File.open(input_file, 'w') do |f|
  f.puts JSON.generate({ key: 'customer:user@example.com:object', dump: 'dGVzdA==' })
  f.puts JSON.generate({ key: 'onetime:customer', dump: 'dGVzdA==' })  # V1 instance index
  f.puts JSON.generate({ key: 'metadata:abc123:object', dump: 'dGVzdA==' })  # Wrong prefix
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

groups = transformer.send(:group_records_by_customer)

# Only customer:user@example.com should be grouped
groups.keys
#=> ["user@example.com"]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## Keys with less than 3 parts are skipped
@temp_dir = Dir.mktmpdir('customer_test')
input_file = File.join(@temp_dir, 'customer_dump.jsonl')

File.open(input_file, 'w') do |f|
  f.puts JSON.generate({ key: 'customer:instances', dump: 'dGVzdA==' })  # 2-part key
  f.puts JSON.generate({ key: 'customer', dump: 'dGVzdA==' })  # 1-part key
end

transformer = CustomerTransformer.new(
  input_file: input_file,
  output_dir: @temp_dir,
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

groups = transformer.send(:group_records_by_customer)

# No groups should be created for keys with < 3 parts
groups.keys.size
#=> 0

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true
