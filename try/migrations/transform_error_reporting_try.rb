# try/migrations/transform_error_reporting_try.rb
#
# frozen_string_literal: true

# Verifies per-record error bucketing in the v0.24.5 transforms after the
# typed-payload (fields_b64) cleanup. Pre-cleanup the failure modes were
# Redis::CommandError from RESTORE/HGETALL; post-cleanup they are Base64::Error
# (ArgumentError subclass) from strict_decode64, plus missing-field detection
# in lib/v1_hash.rb.
#
# What this test exercises (against SecretTransformer.run with a JSONL tmpfile,
# NOT the inner private method, so the rescue chain at lines 158-163 of
# 05-secret/transform.rb is actually traversed):
#
#   A. fields_b64 with one field whose value is not valid Base64
#      -> ArgumentError from Base64.strict_decode64 in V1Hash
#      -> StandardError rescue (line 160) -> :processing_failures
#
#   B. record with no fields_b64 key at all
#      -> V1Hash.read logs to :data_corruption directly (line 28-32)
#      -> read_v1_hash returns nil; process_record returns []
#
#   D. malformed JSON line
#      -> JSON::ParserError rescue (line 158) -> :data_corruption
#
# Schema-gap bucketing for Secret/Receipt/CustomDomain is effectively dead code
# because those transforms build v2_fields from a hardcoded DIRECT_COPY_FIELDS
# list — unknown v1 fields never reach parse_to_ruby_type. Only
# CustomerTransformer has a live :schema_gaps path, and it uses a soft-fail
# inside serialize_for_v2 (line 424-428) with shape {field: key.to_s}, NOT
# {line:, error:}. Tested separately with a customer fixture below (fixture C').

require 'base64'
require 'json'
require 'tempfile'
require 'tmpdir'

PROJECT_ROOT_ERR_TRY = File.expand_path('../..', __dir__).freeze

load File.join(PROJECT_ROOT_ERR_TRY, 'scripts/upgrades/v0.24.5/05-secret/transform.rb')
load File.join(PROJECT_ROOT_ERR_TRY, 'scripts/upgrades/v0.24.5/01-customer/transform.rb')

# --- Helpers ------------------------------------------------------------------

def encode_fields(fields)
  fields.each_with_object({}) do |(k, v), acc|
    acc[k.to_s] = Base64.strict_encode64(v.to_s)
  end
end

# --- Fixture: secret transformer with mixed bad records -----------------------

@workdir = Dir.mktmpdir('xform_err_try_')

# Seed minimal index files so load_mappings finds them. The records below all
# fail before transform_ownership runs, so the index contents don't matter.
%w[customer/customer_indexes.jsonl
   organization/organization_indexes.jsonl
   customdomain/customdomain_indexes.jsonl].each do |rel|
  path = File.join(@workdir, rel)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, '')
end

@secret_input = File.join(@workdir, 'secret_dump.jsonl')

# Fixture A: invalid base64 in fields_b64 -> :processing_failures
record_a = {
  key: 'secret:bad-b64-001:object', type: 'hash', ttl_ms: -1, db: 0,
  fields_b64: { 'ciphertext' => '!!!not-b64!!!' },
}

# Fixture B: missing fields_b64 entirely -> :data_corruption (via V1Hash.read)
record_b = {
  key: 'secret:no-payload-001:object', type: 'hash', ttl_ms: -1, db: 0,
}

# Fixture D: malformed JSON line -> :data_corruption (JSON::ParserError)
malformed_line = '{not valid json'

# Write fixtures to the JSONL input
File.open(@secret_input, 'w') do |f|
  f.puts(JSON.generate(record_a))
  f.puts(JSON.generate(record_b))
  f.puts(malformed_line)
end

@secret_xformer = SecretTransformer.new(
  input_file: @secret_input,
  output_dir: @workdir,
  exports_dir: @workdir,
  dry_run: false, # full path needed: dry_run skips read_v1_hash, defeating the test
)

# Capture stdout/stderr noise from print_summary so test output stays focused.
@orig_stdout = $stdout
$stdout = File.open(File::NULL, 'w')
begin
  @secret_xformer.run
ensure
  $stdout.close
  $stdout = @orig_stdout
end

@secret_stats = @secret_xformer.instance_variable_get(:@stats)
@secret_errors = @secret_stats[:errors]

# --- Fixture C': customer transformer schema_gap (soft-fail path) -------------

@customer_input = File.join(@workdir, 'customer_dump.jsonl')

# A customer record with one unknown field. The transformer's serialize_for_v2
# silently drops the field and records {field: 'totally_bogus_field'} in
# :schema_gaps; the customer record is still emitted (downgraded to a soft fail).
unknown_record = {
  key: 'customer:alice@example.com:object', type: 'hash', ttl_ms: -1, db: 0,
  objid: 'cust-objid-001', extid: 'cu-ext-001', created: 1_700_000_000,
  fields_b64: encode_fields(
    'custid' => 'alice@example.com',
    'email' => 'alice@example.com',
    'created' => '1700000000.0',
    'totally_bogus_field' => 'x',
  ),
}
File.open(@customer_input, 'w') { |f| f.puts(JSON.generate(unknown_record)) }

@customer_xformer = CustomerTransformer.new(
  input_file: @customer_input,
  output_dir: @workdir,
  dry_run: false,
)

@orig_stdout2 = $stdout
$stdout = File.open(File::NULL, 'w')
begin
  @customer_xformer.run
ensure
  $stdout.close
  $stdout = @orig_stdout2
end

@customer_stats = @customer_xformer.instance_variable_get(:@stats)
@customer_errors = @customer_stats[:errors]

# --- Tests --------------------------------------------------------------------

## SecretTransformer.run does not raise to the caller
@secret_stats.is_a?(Hash)
#=> true

## Secret: fixture A (invalid base64) buckets to :processing_failures
@secret_errors[:processing_failures].size
#=> 1

## Secret: fixture A processing_failures entry has :line and :error keys
entry = @secret_errors[:processing_failures].first
entry.key?(:line) && entry.key?(:error) && !entry[:error].to_s.empty?
#=> true

## Secret: fixture B (missing fields_b64) buckets to :data_corruption
# Plus fixture D (malformed JSON) also buckets to :data_corruption
@secret_errors[:data_corruption].size
#=> 2

## Secret: data_corruption from V1Hash includes :key (B) and :error
b_entry = @secret_errors[:data_corruption].find { |e| e[:key] == 'secret:no-payload-001:object' }
b_entry && b_entry[:error] == 'Missing fields_b64 typed payload'
#=> true

## Secret: data_corruption from JSON parse includes :line and :error
parse_entry = @secret_errors[:data_corruption].find { |e| e[:error]&.start_with?('JSON parse error') }
parse_entry && parse_entry.key?(:line)
#=> true

## Secret: orphans bucket untouched by these fixtures
@secret_errors[:orphans].size
#=> 0

## Secret: schema_gaps unreachable for this transformer (DIRECT_COPY only)
@secret_errors[:schema_gaps].size
#=> 0

## Customer: fixture C' (unknown field) recorded in :schema_gaps soft-fail
@customer_errors[:schema_gaps].size
#=> 1

## Customer: schema_gaps entry shape is {field: <name>} (NOT {line:, error:})
sg_entry = @customer_errors[:schema_gaps].first
sg_entry == { field: 'totally_bogus_field' }
#=> true

## Customer: unknown-field soft-fail does NOT bucket to :processing_failures
@customer_errors[:processing_failures].size
#=> 0
