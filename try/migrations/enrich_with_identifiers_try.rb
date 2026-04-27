# try/migrations/enrich_with_identifiers_try.rb
#
# frozen_string_literal: true

# Tests for scripts/upgrades/v0.24.5/enrich_with_identifiers.rb and its
# integration with scripts/upgrades/v0.24.5/run_pipeline.sh.
#
# Regression context (#3036): commit a6531d7a5 (PR #2748, 2026-03-23) flipped
# the script's default to dry-run and renamed --dry-run to --execute, but did
# not update run_pipeline.sh to pass --execute. Pipeline runs silently no-oped
# the enrichment step on v0.24.6+. There was no test exercising the
# script-calls-script boundary, so the bug shipped.
#
# What these tests lock in:
#   1. run_pipeline.sh invokes the enricher with --execute (cheap grep test).
#   2. Invoking the script the way run_pipeline.sh does writes objid/extid into
#      the output JSONL for both ObjectIdentifier models.
#   3. Running the enrichment twice on the same dump is idempotent.
#   4. Invoking with no flags (the standalone default) is dry-run and writes
#      nothing to the output directory.
#
# Implementation notes:
#   - Tests shell out via Open3 rather than requiring IdentifierEnricher
#     directly. The regression was in the CLI contract, not the class. Direct
#     class testing would have passed before and after the regression.
#   - Tests are pure file IO (no Redis, no Onetime boot).
#   - Fixture records mirror the dump_keys.rb output shape: key, type, ttl_ms,
#     db, dump (base64), created.

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

PROJECT_ROOT  = File.expand_path('../..', __dir__).freeze
ENRICH_SCRIPT = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/enrich_with_identifiers.rb').freeze
PIPELINE_SH   = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/run_pipeline.sh').freeze

UUID_V7_RE  = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
EXTID_UR_RE = /\Aur[0-9a-z]{25}\z/.freeze
EXTID_CD_RE = /\Acd[0-9a-z]{25}\z/.freeze

def stage_fixture(input_dir)
  customer_dir     = File.join(input_dir, 'customer')
  customdomain_dir = File.join(input_dir, 'customdomain')
  FileUtils.mkdir_p(customer_dir)
  FileUtils.mkdir_p(customdomain_dir)

  customer_records = [
    { 'key' => 'customer:alice@example.com:object', 'type' => 'hash', 'ttl_ms' => -1, 'db' => 0,
      'dump' => 'AAAA', 'created' => 1_700_000_000.0 },
    { 'key' => 'customer:bob@example.com:object',   'type' => 'hash', 'ttl_ms' => -1, 'db' => 0,
      'dump' => 'BBBB', 'created' => 1_700_000_100.5 },
  ]

  customdomain_records = [
    { 'key' => 'customdomain:abc123:object', 'type' => 'hash', 'ttl_ms' => -1, 'db' => 0,
      'dump' => 'CCCC', 'created' => 1_700_000_200.0 },
  ]

  File.write(File.join(customer_dir, 'customer_dump.jsonl'),
             customer_records.map { |r| JSON.generate(r) }.join("\n") + "\n")
  File.write(File.join(customdomain_dir, 'customdomain_dump.jsonl'),
             customdomain_records.map { |r| JSON.generate(r) }.join("\n") + "\n")
end

def read_jsonl(path)
  File.foreach(path).map { |line| JSON.parse(line.chomp) }
end

def run_enricher(input_dir:, output_dir:, execute: false)
  args = ['ruby', ENRICH_SCRIPT, "--input-dir=#{input_dir}", "--output-dir=#{output_dir}"]
  args << '--execute' if execute
  Open3.capture3(*args, chdir: PROJECT_ROOT)
end

# ---- Pipeline shape: run_pipeline.sh must pass --execute ----------------------

## run_pipeline.sh exists at the expected path
File.exist?(PIPELINE_SH)
#=> true

## run_pipeline.sh invokes enrich_with_identifiers.rb with the --execute flag
File.read(PIPELINE_SH).match?(/enrich_with_identifiers\.rb\s+--execute\b/)
#=> true

## run_pipeline.sh aborts when the enricher prints the dry-run banner
# Belt-and-suspenders for the same regression: even if --execute is dropped,
# the pipeline must fail loudly rather than letting downstream transforms read
# unenriched dumps.
@pipeline_src = File.read(PIPELINE_SH)
[@pipeline_src.include?('Would enrich'), @pipeline_src.match?(/FATAL:\s+enrich_with_identifiers\.rb/)]
#=> [true, true]

# ---- Pipeline-equivalent invocation enriches both models ----------------------

## Setup: fixture under a fresh tmpdir, simulating dump_keys.rb output
@pipeline_dir = Dir.mktmpdir('enrich_pipeline_')
stage_fixture(@pipeline_dir)
@pipeline_status = run_enricher(input_dir: @pipeline_dir, output_dir: @pipeline_dir, execute: true).last
@pipeline_status.success?
#=> true

## Customer records gain objid in UUIDv7 format
@customer_after = read_jsonl(File.join(@pipeline_dir, 'customer', 'customer_dump.jsonl'))
@customer_after.all? { |r| r['objid'].is_a?(String) && r['objid'].match?(UUID_V7_RE) }
#=> true

## Customer records gain extid with the 'ur' prefix
@customer_after.all? { |r| r['extid'].is_a?(String) && r['extid'].match?(EXTID_UR_RE) }
#=> true

## Customer fixture record count is preserved
@customer_after.size
#=> 2

## Customdomain records gain objid in UUIDv7 format and extid with 'cd' prefix
@customdomain_after = read_jsonl(File.join(@pipeline_dir, 'customdomain', 'customdomain_dump.jsonl'))
[@customdomain_after.size,
 @customdomain_after.all? { |r| r['objid'].match?(UUID_V7_RE) },
 @customdomain_after.all? { |r| r['extid'].match?(EXTID_CD_RE) }]
#=> [1, true, true]

## Original payload fields (key, dump, created) are preserved
@customer_after.first.values_at('key', 'dump', 'created')
#=> ["customer:alice@example.com:object", "AAAA", 1700000000.0]

# ---- Idempotency: rerunning yields identical objids ---------------------------

## Capture objids/extids from the first execute pass
@first_pass = @customer_after.map { |r| [r['key'], r['objid'], r['extid']] }
@first_pass.size
#=> 2

## Second --execute pass on the same dump succeeds without error
@second_status = run_enricher(input_dir: @pipeline_dir, output_dir: @pipeline_dir, execute: true).last
@second_status.success?
#=> true

## Identifiers are stable across runs (same objid and extid for each key)
@second_pass = read_jsonl(File.join(@pipeline_dir, 'customer', 'customer_dump.jsonl'))
                 .map { |r| [r['key'], r['objid'], r['extid']] }
@second_pass == @first_pass
#=> true

# ---- Standalone default is dry-run: no writes to output_dir -------------------

## Setup: input_dir under one tmpdir, output_dir under a different empty tmpdir
@dry_input  = Dir.mktmpdir('enrich_dry_in_')
@dry_output = Dir.mktmpdir('enrich_dry_out_')
stage_fixture(@dry_input)
@dry_status = run_enricher(input_dir: @dry_input, output_dir: @dry_output, execute: false).last
@dry_status.success?
#=> true

## Dry-run writes no JSONL files into the output directory
Dir.glob(File.join(@dry_output, '**', '*.jsonl'))
#=> []

## Dry-run leaves the input fixture untouched (no objid added in place)
read_jsonl(File.join(@dry_input, 'customer', 'customer_dump.jsonl')).first.key?('objid')
#=> false

# Teardown: clean up tmpdirs
FileUtils.rm_rf(@pipeline_dir) if @pipeline_dir
FileUtils.rm_rf(@dry_input)    if @dry_input
FileUtils.rm_rf(@dry_output)   if @dry_output
