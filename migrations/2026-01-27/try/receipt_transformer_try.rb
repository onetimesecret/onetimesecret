# try/migrations/receipt_transformer_try.rb
#
# Unit tests for the ReceiptTransformer class from 04-receipt/transform.rb
# Tests receipt data transformation from V1 (metadata) to V2 format.
#
# frozen_string_literal: true

require_relative '../../../try/support/test_helpers'
require 'json'
require 'base64'
require 'fileutils'
require 'tmpdir'

MIGRATION_DIR = File.expand_path('..', __dir__)
load File.join(MIGRATION_DIR, '04-receipt', 'transform.rb')

## ReceiptTransformer has correct TEMP_KEY_PREFIX
ReceiptTransformer::TEMP_KEY_PREFIX
#=> "_migrate_tmp_receipt_"

## STATE_TRANSFORMS maps viewed to previewed
ReceiptTransformer::STATE_TRANSFORMS['viewed']
#=> "previewed"

## STATE_TRANSFORMS maps received to revealed
ReceiptTransformer::STATE_TRANSFORMS['received']
#=> "revealed"

## DIRECT_COPY_FIELDS includes expected fields
required_fields = %w[objid secret_identifier secret_shortid secret_ttl lifespan share_domain]
required_fields.all? { |f| ReceiptTransformer::DIRECT_COPY_FIELDS.include?(f) }
#=> true

## Index file paths are correct
[
  ReceiptTransformer::CUSTOMER_INDEXES_FILE,
  ReceiptTransformer::ORG_INDEXES_FILE,
  ReceiptTransformer::DOMAIN_INDEXES_FILE
]
#=> ["customer/customer_indexes.jsonl", "organization/organization_indexes.jsonl", "customdomain/customdomain_indexes.jsonl"]

## extract_objid extracts from metadata key pattern
transformer = ReceiptTransformer.allocate
transformer.send(:extract_objid, 'metadata:abc123xyz:object')
#=> "abc123xyz"

## extract_objid returns nil for non-matching patterns
transformer = ReceiptTransformer.allocate
transformer.send(:extract_objid, 'metadata:abc123xyz:receipts')
#=> nil

## extract_objid handles UUIDv4 identifiers
transformer = ReceiptTransformer.allocate
uuid = '550e8400-e29b-41d4-a716-446655440000'
transformer.send(:extract_objid, "metadata:#{uuid}:object")
#=> "550e8400-e29b-41d4-a716-446655440000"

## Stats structure includes ownership tracking
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = transformer.instance_variable_get(:@stats)
ownership_keys = %i[anonymous_receipts missing_customer_lookup missing_org_lookup missing_domain_lookup]
ownership_keys.all? { |k| stats.key?(k) }
#=> true

## Stats tracks failed lookup details
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

stats = transformer.instance_variable_get(:@stats)
detail_keys = %i[failed_customer_lookups failed_org_lookups failed_domain_lookups]
detail_keys.all? { |k| stats[k].is_a?(Array) }
#=> true

## validate_input_file raises for missing file
transformer = ReceiptTransformer.new(
  input_file: '/nonexistent/file.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
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

## validate_index_file! raises for missing customer indexes
transformer = ReceiptTransformer.allocate

begin
  transformer.send(:validate_index_file!, '/nonexistent/customer_indexes.jsonl', 'customer')
  false
rescue ArgumentError => e
  e.message.include?('customer') && e.message.include?('not found')
end
#=> true

## transform_ownership handles anonymous receipts (nil custid)
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, nil, nil)

stats = transformer.instance_variable_get(:@stats)
[v2_fields['owner_id'], stats[:anonymous_receipts]]
#=> ["anon", 1]

## transform_ownership handles anonymous receipts (empty custid)
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, '', nil)

v2_fields['owner_id']
#=> "anon"

## transform_ownership handles anonymous receipts ('anon' custid)
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'anon', nil)

v2_fields['owner_id']
#=> "anon"

## transform_ownership records missing customer lookup
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

# Empty lookup tables
transformer.instance_variable_set(:@email_to_customer, {})
transformer.instance_variable_set(:@email_to_org, {})
transformer.instance_variable_set(:@fqdn_to_domain, {})

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'missing@example.com', nil)

stats = transformer.instance_variable_get(:@stats)
is_included_in_array = stats[:failed_customer_lookups].include?('missing@example.com') # not a string comparison
[v2_fields['owner_id'], stats[:missing_customer_lookup], is_included_in_array]
#=> [nil, 1, true]

## transform_ownership uses email_to_customer lookup
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

transformer.instance_variable_set(:@email_to_customer, { 'user@example.com' => 'cust-objid-123' })
transformer.instance_variable_set(:@email_to_org, {})
transformer.instance_variable_set(:@fqdn_to_domain, {})

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'user@example.com', nil)

v2_fields['owner_id']
#=> "cust-objid-123"

## transform_ownership uses email_to_org lookup
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

transformer.instance_variable_set(:@email_to_customer, { 'user@example.com' => 'cust-objid-123' })
transformer.instance_variable_set(:@email_to_org, { 'user@example.com' => 'org-objid-456' })
transformer.instance_variable_set(:@fqdn_to_domain, {})

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'user@example.com', nil)

v2_fields['org_id']
#=> "org-objid-456"

## transform_ownership uses fqdn_to_domain lookup when share_domain set
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

transformer.instance_variable_set(:@email_to_customer, { 'user@example.com' => 'cust-objid' })
transformer.instance_variable_set(:@email_to_org, { 'user@example.com' => 'org-objid' })
transformer.instance_variable_set(:@fqdn_to_domain, { 'secrets.example.com' => 'domain-objid-789' })

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'user@example.com', 'secrets.example.com')

v2_fields['domain_id']
#=> "domain-objid-789"

## transform_ownership tracks missing domain lookup
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

transformer.instance_variable_set(:@email_to_customer, { 'user@example.com' => 'cust-objid' })
transformer.instance_variable_set(:@email_to_org, { 'user@example.com' => 'org-objid' })
transformer.instance_variable_set(:@fqdn_to_domain, {})

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'user@example.com', 'unknown.example.com')

stats = transformer.instance_variable_get(:@stats)
[stats[:missing_domain_lookup], stats[:failed_domain_lookups].include?('unknown.example.com')]
#=> [1, true]

## transform_ownership skips domain lookup when share_domain empty
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

transformer.instance_variable_set(:@email_to_customer, { 'user@example.com' => 'cust-objid' })
transformer.instance_variable_set(:@email_to_org, { 'user@example.com' => 'org-objid' })
transformer.instance_variable_set(:@fqdn_to_domain, { 'some.domain' => 'domain-objid' })

v2_fields = {}
transformer.send(:transform_ownership, v2_fields, 'user@example.com', '')

# No domain_id should be set when share_domain is empty
v2_fields.key?('domain_id')
#=> false

## load_index_file parses HSET commands correctly
@temp_dir = Dir.mktmpdir('receipt_test')

# Create a mock index file
index_file = File.join(@temp_dir, 'test_indexes.jsonl')
File.open(index_file, 'w') do |f|
  f.puts JSON.generate({
    command: 'HSET',
    key: 'customer:email_index',
    args: ['user@example.com', '"cust-objid-123"']
  })
  f.puts JSON.generate({
    command: 'ZADD',  # Should be skipped (not HSET)
    key: 'customer:instances',
    args: [1706000000, 'cust-objid-123']
  })
end

transformer = ReceiptTransformer.allocate
results = []
transformer.send(:load_index_file, index_file, 'customer:email_index') do |email, objid|
  results << [email, objid]
end

results
#=> [["user@example.com", "cust-objid-123"]]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## load_index_file filters by target key
@temp_dir = Dir.mktmpdir('receipt_test')

index_file = File.join(@temp_dir, 'test_indexes.jsonl')
File.open(index_file, 'w') do |f|
  f.puts JSON.generate({
    command: 'HSET',
    key: 'customer:email_index',
    args: ['user@example.com', '"cust-objid"']
  })
  f.puts JSON.generate({
    command: 'HSET',
    key: 'customer:extid_lookup',  # Different key
    args: ['urextid123', '"cust-objid"']
  })
end

transformer = ReceiptTransformer.allocate
results = []
transformer.send(:load_index_file, index_file, 'customer:email_index') do |lookup, objid|
  results << lookup
end

# Should only include email_index entry, not extid_lookup
results
#=> ["user@example.com"]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## process_record skips non-object keys
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

line = JSON.generate({ key: 'metadata:abc123:receipts' })
result = transformer.send(:process_record, line)
result
#=> []

## process_record skips non-metadata prefixed keys
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

line = JSON.generate({ key: 'customer:user@example.com:object' })
result = transformer.send(:process_record, line)
result
#=> []

## process_record skips empty lines
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

result = transformer.send(:process_record, '')
result
#=> []

## dry_run mode returns empty from process_record for valid input
transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: '/tmp',
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: true
)

line = JSON.generate({ key: 'metadata:abc123:object', dump: 'dGVzdA==' })
result = transformer.send(:process_record, line)
result
#=> []

## Output filename is receipts_transformed.jsonl
@temp_dir = Dir.mktmpdir('receipt_test')

transformer = ReceiptTransformer.new(
  input_file: '/tmp/test.jsonl',
  output_dir: @temp_dir,
  exports_dir: '/tmp',
  redis_url: 'redis://127.0.0.1:6379',
  temp_db: 15,
  dry_run: false
)

records = [{ key: 'receipt:abc123:object', dump: 'dGVzdA==' }]
transformer.send(:write_output, records)

File.exist?(File.join(@temp_dir, 'receipts_transformed.jsonl'))
#=> true

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true
