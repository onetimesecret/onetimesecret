# try/migrations/identifier_enricher_try.rb
#
# Unit tests for the IdentifierEnricher class from enrich_with_identifiers.rb
# Tests UUIDv7 generation, extid derivation, and record enrichment logic.
#
# frozen_string_literal: true

require_relative '../support/test_helpers'
require 'json'
require 'securerandom'
require 'digest'
require 'fileutils'
require 'tmpdir'

# Load the enricher class directly (standalone, no OT dependencies)
MIGRATION_DIR = File.expand_path('../../migrations/2026-01-26', __dir__)
load File.join(MIGRATION_DIR, 'enrich_with_identifiers.rb')

## UUIDv7 format validation - basic structure
# UUIDv7 has format: xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx
# where 7 is version and y is variant (8, 9, a, or b)
timestamp = 1706000000  # Fixed timestamp for testing
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = enricher.send(:generate_uuid_v7_from, timestamp)

# Check format: 8-4-4-4-12 hex chars with hyphens
uuid.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
#=> true

## UUIDv7 timestamp encoding - milliseconds in first 48 bits
# The first 12 hex chars (48 bits) encode milliseconds since epoch
timestamp = 1706000000
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = enricher.send(:generate_uuid_v7_from, timestamp)

# Extract timestamp from UUID
hex_no_hyphens = uuid.delete('-')
timestamp_hex = hex_no_hyphens[0, 12]
extracted_ms = timestamp_hex.to_i(16)
extracted_seconds = extracted_ms / 1000

# Should match original timestamp (within 1 second due to rounding)
(extracted_seconds - timestamp).abs <= 1
#=> true

## UUIDv7 version bit is 7
timestamp = 1706000000
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = enricher.send(:generate_uuid_v7_from, timestamp)

# Version is the 13th hex char (index 14 in string with hyphens)
version_char = uuid[14]
version_char
#=> "7"

## UUIDv7 variant bits are correct (10xx pattern)
timestamp = 1706000000
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = enricher.send(:generate_uuid_v7_from, timestamp)

# Variant is the 17th hex char (after third hyphen)
variant_char = uuid[19]
['8', '9', 'a', 'b'].include?(variant_char)
#=> true

## ExtID derivation is deterministic - same input produces same output
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = '0190a0b0-c0d0-7e00-f000-000000000001'

extid1 = enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
extid2 = enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')

extid1 == extid2
#=> true

## ExtID prefix matches model - customer gets 'ur'
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = '0190a0b0-c0d0-7e00-f000-000000000001'

extid = enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
extid.start_with?('ur')
#=> true

## ExtID prefix matches model - customdomain gets 'cd'
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = '0190a0b0-c0d0-7e00-f000-000000000001'

extid = enricher.send(:derive_extid_from_uuid, uuid, prefix: 'cd')
extid.start_with?('cd')
#=> true

## ExtID length is 27 chars (2 prefix + 25 base36)
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')
uuid = '0190a0b0-c0d0-7e00-f000-000000000001'

extid = enricher.send(:derive_extid_from_uuid, uuid, prefix: 'ur')
extid.length
#=> 27

## should_enrich? returns true for :object with created
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object', 'created' => 1706000000 }
enricher.send(:should_enrich?, record)
#=> true

## should_enrich? returns false for non-:object keys
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:receipts', 'created' => 1706000000 }
enricher.send(:should_enrich?, record)
#=> false

## should_enrich? returns falsy for :object without created
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object', 'created' => nil }
result = enricher.send(:should_enrich?, record)
# Returns nil (falsy) because nil&.positive? is nil
!!result
#=> false

## should_enrich? returns false for :object with zero created
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object', 'created' => 0 }
enricher.send(:should_enrich?, record)
#=> false

## rename_key! transforms :metadata to :receipts
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:metadata' }
result = enricher.send(:rename_key!, record)

[result, record['key']]
#=> [true, "customer:test@example.com:receipts"]

## rename_key! returns false for non-matching keys
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object' }
result = enricher.send(:rename_key!, record)

[result, record['key']]
#=> [false, "customer:test@example.com:object"]

## enrich_record! adds objid and extid to record
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object', 'created' => 1706000000 }
enricher.send(:enrich_record!, record, 'ur')

[record.key?('objid'), record.key?('extid')]
#=> [true, true]

## enrich_record! generates valid objid format
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object', 'created' => 1706000000 }
enricher.send(:enrich_record!, record, 'ur')

record['objid'].match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
#=> true

## enrich_record! generates extid with correct prefix
enricher = IdentifierEnricher.new(input_dir: '/tmp', output_dir: '/tmp')

record = { 'key' => 'customer:test@example.com:object', 'created' => 1706000000 }
enricher.send(:enrich_record!, record, 'cd')

record['extid'].start_with?('cd')
#=> true

## EXTID_PREFIXES has correct model mappings
IdentifierEnricher::EXTID_PREFIXES
#=> {"customer"=>"ur", "customdomain"=>"cd", "organization"=>"on"}

## MODELS_TO_ENRICH excludes organization (created fresh, not imported)
IdentifierEnricher::MODELS_TO_ENRICH.include?('organization')
#=> false

## MODELS_TO_ENRICH includes customer and customdomain
[
  IdentifierEnricher::MODELS_TO_ENRICH.include?('customer'),
  IdentifierEnricher::MODELS_TO_ENRICH.include?('customdomain')
]
#=> [true, true]

## Full enrichment with temp files
@temp_dir = Dir.mktmpdir('enricher_test')

# Create input directory structure
input_dir = File.join(@temp_dir, 'input')
output_dir = File.join(@temp_dir, 'output')
FileUtils.mkdir_p(File.join(input_dir, 'customer'))
FileUtils.mkdir_p(File.join(output_dir, 'customer'))

# Write test input file
input_file = File.join(input_dir, 'customer', 'customer_dump.jsonl')
File.open(input_file, 'w') do |f|
  f.puts JSON.generate({
    key: 'customer:test@example.com:object',
    type: 'hash',
    ttl_ms: -1,
    db: 6,
    dump: 'dGVzdA==',  # base64 "test"
    created: 1706000000
  })
  f.puts JSON.generate({
    key: 'customer:test@example.com:receipts',
    type: 'zset',
    ttl_ms: -1,
    db: 6,
    dump: 'dGVzdA=='
  })
end

enricher = IdentifierEnricher.new(
  input_dir: input_dir,
  output_dir: output_dir,
  dry_run: false
)
stats = enricher.run

# Check stats
[stats['customer'][:enriched], stats['customer'][:skipped]]
#=> [1, 1]

## Full enrichment produces valid output file
# Read output from the temp directory created in previous test
output_file = File.join(@temp_dir, 'output', 'customer', 'customer_dump.jsonl')
@output_lines = File.readlines(output_file)

# First line should have objid/extid
first_record = JSON.parse(@output_lines[0])
[first_record.key?('objid'), first_record.key?('extid'), first_record['key']]
#=> [true, true, "customer:test@example.com:object"]

## Non-object records pass through without objid/extid
# Use lines from previous test
second_record = JSON.parse(@output_lines[1])
[second_record.key?('objid'), second_record.key?('extid')]
#=> [false, false]

## Cleanup temp directory
FileUtils.rm_rf(@temp_dir)
true
#=> true

## Dry-run mode does not write files
@temp_dir = Dir.mktmpdir('enricher_test')
input_dir = File.join(@temp_dir, 'input')
output_dir = File.join(@temp_dir, 'output')
FileUtils.mkdir_p(File.join(input_dir, 'customer'))

input_file = File.join(input_dir, 'customer', 'customer_dump.jsonl')
File.open(input_file, 'w') do |f|
  f.puts JSON.generate({
    key: 'customer:test@example.com:object',
    created: 1706000000
  })
end

enricher = IdentifierEnricher.new(
  input_dir: input_dir,
  output_dir: output_dir,
  dry_run: true
)
stats = enricher.run

# Output directory should not be created in dry-run
output_file = File.join(output_dir, 'customer', 'customer_dump.jsonl')
File.exist?(output_file)
#=> false

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true

## JSON parse errors are collected, not thrown
@temp_dir = Dir.mktmpdir('enricher_test')
input_dir = File.join(@temp_dir, 'input')
output_dir = File.join(@temp_dir, 'output')
FileUtils.mkdir_p(File.join(input_dir, 'customer'))
FileUtils.mkdir_p(File.join(output_dir, 'customer'))

input_file = File.join(input_dir, 'customer', 'customer_dump.jsonl')
File.open(input_file, 'w') do |f|
  f.puts 'not valid json {'
  f.puts JSON.generate({
    key: 'customer:test@example.com:object',
    created: 1706000000
  })
end

enricher = IdentifierEnricher.new(
  input_dir: input_dir,
  output_dir: output_dir,
  dry_run: false
)
stats = enricher.run

# Should have recorded an error but still processed valid record
[stats['customer'][:errors].size > 0, stats['customer'][:enriched]]
#=> [true, 1]

## Cleanup
FileUtils.rm_rf(@temp_dir)
true
#=> true
