# try/unit/scripts/original_record_restorer_try.rb
#
# frozen_string_literal: true

# Structural and unit tests for OriginalRecordRestorer.
# Tests configuration, mapping logic, helpers, and argument parsing
# without requiring a live Redis connection or real migration data.

require_relative '../../../scripts/upgrades/v0.24.0/enrich_with_original_record'

@restorer = OriginalRecordRestorer.new(
  input_dir: '/tmp/nonexistent',
  redis_url: 'redis://localhost:6379',
  target_db: 0,
  dry_run: true,
)

## OriginalRecordRestorer class is defined
defined?(OriginalRecordRestorer)
#=> "constant"

## Instance responds to run
@restorer.respond_to?(:run)
#=> true

## THIRTY_DAYS_MS constant is 30 days in milliseconds
OriginalRecordRestorer::THIRTY_DAYS_MS
#=> 2_592_000_000

## TEMP_KEY_PREFIX constant is set
OriginalRecordRestorer::TEMP_KEY_PREFIX
#=> "_restore_mapping_tmp_"

## MODEL_CONFIG is frozen
OriginalRecordRestorer::MODEL_CONFIG.frozen?
#=> true

## MODEL_CONFIG has all 4 model types
OriginalRecordRestorer::MODEL_CONFIG.keys.sort
#=> ["customdomain", "customer", "metadata", "secret"]

## Every model config has required keys
required_keys = %i[v1_prefix v2_prefix related_suffixes dir dump_file transformed_file]
OriginalRecordRestorer::MODEL_CONFIG.all? { |_model, cfg|
  required_keys.all? { |k| cfg.key?(k) }
}
#=> true

## Customer config maps v1 customer to v2 customer
cfg = OriginalRecordRestorer::MODEL_CONFIG['customer']
[cfg[:v1_prefix], cfg[:v2_prefix]]
#=> ["customer", "customer"]

## Customdomain config maps v1 customdomain to v2 custom_domain
cfg = OriginalRecordRestorer::MODEL_CONFIG['customdomain']
[cfg[:v1_prefix], cfg[:v2_prefix]]
#=> ["customdomain", "custom_domain"]

## Metadata config maps v1 metadata to v2 receipt
cfg = OriginalRecordRestorer::MODEL_CONFIG['metadata']
[cfg[:v1_prefix], cfg[:v2_prefix]]
#=> ["metadata", "receipt"]

## Secret config maps v1 secret to v2 secret
cfg = OriginalRecordRestorer::MODEL_CONFIG['secret']
[cfg[:v1_prefix], cfg[:v2_prefix]]
#=> ["secret", "secret"]

## Customdomain has multiple related suffixes
OriginalRecordRestorer::MODEL_CONFIG['customdomain'][:related_suffixes].sort
#=> ["brand", "icon", "logo", "object"]

## Customer has only object suffix
OriginalRecordRestorer::MODEL_CONFIG['customer'][:related_suffixes]
#=> ["object"]

## Each model config has correct dump_file naming
OriginalRecordRestorer::MODEL_CONFIG.all? { |_model, cfg|
  cfg[:dump_file].end_with?('_dump.jsonl')
}
#=> true

## Each model config has correct transformed_file naming
OriginalRecordRestorer::MODEL_CONFIG.all? { |_model, cfg|
  cfg[:transformed_file].end_with?('_transformed.jsonl')
}
#=> true

## Metadata transformed_file uses receipt prefix (not metadata)
OriginalRecordRestorer::MODEL_CONFIG['metadata'][:transformed_file]
#=> "receipt_transformed.jsonl"

## extract_suffix returns last colon-separated segment
@restorer.send(:extract_suffix, 'customer:user@example.com:object')
#=> "object"

## extract_suffix handles brand suffix
@restorer.send(:extract_suffix, 'customdomain:example.com:brand')
#=> "brand"

## extract_suffix returns whole key when no colon present
@restorer.send(:extract_suffix, 'noprefix')
#=> "noprefix"

## strip_suffix returns everything before last colon
@restorer.send(:strip_suffix, 'customer:user@example.com:object')
#=> "customer:user@example.com"

## strip_suffix handles multiple colons
@restorer.send(:strip_suffix, 'customdomain:sub.example.com:brand')
#=> "customdomain:sub.example.com"

## strip_suffix returns whole key when no colon present
@restorer.send(:strip_suffix, 'noprefix')
#=> "noprefix"

## parse_args returns defaults when no args given
opts = parse_args([])
[opts[:input_dir], opts[:target_db], opts[:dry_run]]
#=> ["data/upgrades/v0.24.0", 0, false]

## parse_args recognizes --dry-run flag
opts = parse_args(['--dry-run'])
opts[:dry_run]
#=> true

## parse_args parses --input-dir
opts = parse_args(['--input-dir=/custom/path'])
opts[:input_dir]
#=> "/custom/path"

## parse_args parses --target-db as integer
opts = parse_args(['--target-db=5'])
opts[:target_db]
#=> 5

## parse_args parses --redis-url
opts = parse_args(['--redis-url=redis://myhost:6380'])
opts[:redis_url]
#=> "redis://myhost:6380"

## parse_args handles multiple options together
opts = parse_args(['--dry-run', '--input-dir=/data', '--target-db=3'])
[opts[:dry_run], opts[:input_dir], opts[:target_db]]
#=> [true, "/data", 3]

## parse_args exits on unknown option
begin
  parse_args(['--bogus'])
  'should have exited'
rescue SystemExit => ex
  ex.status
end
#=> 1

## Dry-run instance does not attempt Redis connection on run
# With nonexistent input files, process_model skips each model gracefully
restorer = OriginalRecordRestorer.new(
  input_dir: '/tmp/nonexistent_dir_for_test',
  redis_url: 'redis://localhost:6379',
  target_db: 0,
  dry_run: true,
)
result = restorer.run
result.is_a?(Hash)
#=> true

## Stats hash uses default proc for per-model counters
restorer = OriginalRecordRestorer.new(
  input_dir: '/tmp/nonexistent',
  redis_url: 'redis://localhost:6379',
  target_db: 0,
  dry_run: true,
)
stats = restorer.instance_variable_get(:@stats)
stats['test_model'][:mapped]
#=> 0

## Stats default has all expected counter keys
restorer = OriginalRecordRestorer.new(
  input_dir: '/tmp/nonexistent',
  redis_url: 'redis://localhost:6379',
  target_db: 0,
  dry_run: true,
)
stats = restorer.instance_variable_get(:@stats)
entry = stats['any_model']
entry.keys.sort
#=> [:errors, :mapped, :not_found, :restored, :skipped]

## build_mapping_from_dump parses enriched dump JSONL with objid
require 'tempfile'
require 'json'

tmpfile = Tempfile.new(['dump', '.jsonl'])
tmpfile.puts({ key: 'customer:alice@example.com:object', objid: 'abc-123', dump: 'base64data' }.to_json)
tmpfile.puts({ key: 'customer:alice@example.com:metadata', dump: 'base64data' }.to_json)
tmpfile.puts({ key: 'customer:bob@example.com:object', objid: 'def-456', dump: 'base64data' }.to_json)
tmpfile.close

mapping = @restorer.send(:build_mapping_from_dump, tmpfile.path)
mapping
#=> {"customer:alice@example.com"=>"abc-123", "customer:bob@example.com"=>"def-456"}

## build_mapping_from_dump skips lines without objid
tmpfile = Tempfile.new(['dump', '.jsonl'])
tmpfile.puts({ key: 'secret:xyz:object', dump: 'base64data' }.to_json)
tmpfile.close

mapping = @restorer.send(:build_mapping_from_dump, tmpfile.path)
mapping
#=> {}

## build_mapping_from_dump skips malformed JSON lines
tmpfile = Tempfile.new(['dump', '.jsonl'])
tmpfile.puts('not valid json{{{')
tmpfile.puts({ key: 'customer:c@d.com:object', objid: 'ghi-789', dump: 'x' }.to_json)
tmpfile.close

mapping = @restorer.send(:build_mapping_from_dump, tmpfile.path)
mapping.size
#=> 1
