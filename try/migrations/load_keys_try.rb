# try/migrations/load_keys_try.rb
#
# frozen_string_literal: true

# Tests for scripts/upgrades/v0.24.5/load_keys.rb and its integration with
# scripts/upgrades/v0.24.5/upgrade.sh (Phase 3).
#
# Regression context (#3041):
#   1. A missing {model}_transformed.jsonl was logged but did not fail the
#      script — load_keys.rb returned 0 even when an entire model's records
#      were absent. Operators only learned about the gap from a keyspace
#      diff after the fact.
#   2. Help/banner/comments in load_keys.rb still mentioned legacy DBs 6/7/8
#      after the consolidation onto DB 0. Misleading for anyone reading the
#      help to understand the layout.
#   3. upgrade.sh invoked load_keys.rb without an explicit `$?` check, so
#      an exiting-1 loader could be masked by surrounding script structure.
#
# Post-fix contract:
#   * Help text shows DB 0 for every model and contains no DB 6/7/8 mentions.
#   * Missing transformed file is recorded as an error and load_keys.rb
#     exits 1 (via the existing exit_with_status hook).
#   * --skip-records suppresses the missing-records error path (operator
#     opt-in for indexes-only loads).
#   * upgrade.sh Phase 3 captures load_keys_rc and aborts with the same
#     non-zero code, printing a FATAL line.
#
# Implementation notes:
#   * Tests shell out via Open3. The contracts under test are CLI-shaped.
#   * Help-text and missing-artifact cases are pure file IO (no Redis).
#   * Happy-path / --skip-records / upgrade.sh propagation cases need a
#     reachable test Redis. Tests skip gracefully if no Redis is available;
#     the suite must never crash on a developer laptop without Redis.
#   * Test Redis target defaults to redis://localhost:6379/15 (DB 15) and
#     namespaces all writes under a tmp prefix for safe cleanup.

require 'base64'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'uri'

PROJECT_ROOT     = File.expand_path('../..', __dir__).freeze
LOAD_KEYS_SCRIPT = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/load_keys.rb').freeze
UPGRADE_SH       = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/upgrade.sh').freeze

TEST_VALKEY_URL = ENV['TEST_VALKEY_URL'] || ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://localhost:6379/15'

def redis_available?
  return @redis_available unless @redis_available.nil?

  require 'redis'
  uri = URI.parse(TEST_VALKEY_URL)
  uri.path = '/15'
  client = Redis.new(url: uri.to_s, timeout: 1)
  client.ping
  client.close
  @redis_available = true
rescue LoadError, StandardError
  @redis_available = false
end

# Stage every model subdir load_keys.rb expects to find. Files written depend
# on the +files+ keyword: pass {transformed: true, indexes: true} to populate
# both, or omit either to test the missing-artifact paths.
#
# +records+ is keyed by model name; values are arrays of record hashes that
# get serialized as transformed JSONL. Index commands are a small fixed shape
# unless +indexes+ is a Hash.
def stage_input_dir(input_dir, files: {}, records: {})
  layout = {
    'customer'     => 'customer',
    'organization' => 'organization',
    'customdomain' => 'customdomain',
    'receipt'      => 'metadata',
    'secret'       => 'secret',
  }

  layout.each do |model, subdir|
    dir = File.join(input_dir, subdir)
    FileUtils.mkdir_p(dir)

    if files[:transformed]
      transformed_path = File.join(dir, "#{model}_transformed.jsonl")
      lines = (records[model] || []).map { |r| JSON.generate(r) }
      File.write(transformed_path, lines.join("\n") + (lines.empty? ? '' : "\n"))
    end

    if files[:indexes]
      indexes_path = File.join(dir, "#{model}_indexes.jsonl")
      File.write(indexes_path, '') # empty indexes file is valid input
    end
  end
end

def run_load_keys(args, env: {})
  Open3.capture3(env, 'ruby', LOAD_KEYS_SCRIPT, *args, chdir: PROJECT_ROOT)
end

# Build a record whose `dump` is a real Redis SERIALIZE blob for an empty
# hash — RESTORE accepts this on any DB without needing a prior dump. Only
# used when Redis is available; the byte sequence comes from Redis itself.
def hash_dump_blob(redis)
  redis.del('__test_seed__')
  redis.hset('__test_seed__', 'k', 'v')
  blob = redis.dump('__test_seed__')
  redis.del('__test_seed__')
  blob
end

# ---- Help text contract (#3041) -----------------------------------------------

## Setup: capture --help output once for reuse across assertions
@help_stdout, _, @help_status = run_load_keys(['--help'])
@help_status.success?
#=> true

## Help text mentions DB 0 (the consolidated target database)
@help_stdout.match?(/\bDB 0\b/)
#=> true

## Help text contains zero references to legacy DBs 6, 7, or 8
@help_stdout.match?(/\bDB\s*[678]\b/)
#=> false

## Help text enumerates all five models on DB 0
%w[customer organization customdomain receipt secret].all? do |m|
  @help_stdout.match?(/#{m}\s+->\s+DB 0/)
end
#=> true

# ---- Missing transformed file fails loudly (#3041) ----------------------------

## Setup: stage every model's subdir but write no transformed files.
## Indexes files are present so the indexes path doesn't also error.
## Use --model=customer so the run does not need Redis to surface the
## missing-artifact error: load_keys.rb records the error before opening
## any connection. The all-models case is covered when Redis is reachable.
@missing_dir = Dir.mktmpdir('load_keys_missing_')
stage_input_dir(@missing_dir, files: { indexes: true })
@missing_stdout, @missing_stderr, @missing_status =
  run_load_keys(["--input-dir=#{@missing_dir}", "--valkey-url=#{TEST_VALKEY_URL}",
                 '--model=customer', '--skip-indexes', '--dry-run'])
@missing_status.exitstatus
#=> 1

## Stderr names the model whose transformed file is missing
@missing_stderr.match?(/Missing transformed file.*customer/)
#=> true

## When Redis is reachable, run with no --model and confirm every model's
## missing transformed file is reported (no silent passes).
if redis_available?
  _, @all_missing_stderr, @all_missing_status =
    run_load_keys(["--input-dir=#{@missing_dir}", "--valkey-url=#{TEST_VALKEY_URL}", '--dry-run'])
end

## Exit status is 1 across-the-board when Redis is reachable.
redis_available? ? @all_missing_status.exitstatus : 1
#=> 1

## All five models report a missing transformed file (Redis-required check).
if redis_available?
  %w[customer organization customdomain receipt secret].all? do |m|
    @all_missing_stderr.match?(/Missing transformed file.*#{m}/)
  end
else
  true
end
#=> true

# Teardown for missing-artifact case
FileUtils.rm_rf(@missing_dir) if @missing_dir

# ---- --skip-records bypasses the missing-records check (#3041) ----------------

## Setup: index files only, no transformed JSONL anywhere. With --skip-records,
## load_keys.rb should not record errors for absent transformed files.
@skip_dir = Dir.mktmpdir('load_keys_skip_')
stage_input_dir(@skip_dir, files: { indexes: true })

## Skip gracefully if no Redis: --skip-records still opens connections to
## execute (empty) index files, so we cannot run this case offline.
@skip_stdout, @skip_stderr, @skip_status =
  if redis_available?
    run_load_keys(["--input-dir=#{@skip_dir}", "--valkey-url=#{TEST_VALKEY_URL}", '--skip-records'])
  else
    [nil, nil, nil]
  end

## Exits 0 when Redis is reachable; skipped otherwise (no false failure).
redis_available? ? @skip_status.exitstatus : 0
#=> 0

## Stderr does not contain a "Missing transformed file" error in skip mode.
redis_available? ? !@skip_stderr.include?('Missing transformed file') : true
#=> true

# Teardown for skip-records case
FileUtils.rm_rf(@skip_dir) if @skip_dir

# ---- Happy path: one customer, no indexes, --skip-indexes ---------------------

## Setup: a single transformed customer record using a real Redis dump blob.
## All other models keep empty transformed files so they don't error out.
@happy_dir = Dir.mktmpdir('load_keys_happy_')

if redis_available?
  require 'redis'
  uri = URI.parse(TEST_VALKEY_URL); uri.path = '/15'
  @happy_redis = Redis.new(url: uri.to_s, timeout: 2)
  @happy_redis.flushdb
  @happy_blob   = hash_dump_blob(@happy_redis)
  @happy_record = {
    'key'    => 'tryouts:load_keys:customer:alice@example.com:object',
    'type'   => 'hash',
    'ttl_ms' => -1,
    'db'     => 0,
    'dump'   => Base64.strict_encode64(@happy_blob),
  }
  stage_input_dir(@happy_dir,
                  files:   { transformed: true },
                  records: { 'customer' => [@happy_record] })

  uri15 = URI.parse(TEST_VALKEY_URL); uri15.path = '/15'
  @happy_stdout, @happy_stderr, @happy_status =
    run_load_keys(["--input-dir=#{@happy_dir}", "--valkey-url=#{uri15}",
                   '--model=customer', '--skip-indexes'])
end

## Exits 0 when Redis is reachable; skipped otherwise.
redis_available? ? @happy_status.exitstatus : 0
#=> 0

## Summary output reports the restored record count.
redis_available? ? @happy_stdout.match?(/Records restored:\s+1/) : true
#=> true

## The record actually landed in the target DB.
if redis_available?
  exists = @happy_redis.exists?('tryouts:load_keys:customer:alice@example.com:object')
  @happy_redis.del('tryouts:load_keys:customer:alice@example.com:object')
  @happy_redis.flushdb
  @happy_redis.close
  exists
else
  true
end
#=> true

# Teardown for happy path
FileUtils.rm_rf(@happy_dir) if @happy_dir

# ---- upgrade.sh propagates load_keys.rb non-zero exit (#3041) -----------------

## upgrade.sh structurally captures the load_keys.rb return code (regression
## guard: even if the bash flow is rewritten, this file-level check ensures
## the exit-status propagation pattern stays in place).
@upgrade_src = File.read(UPGRADE_SH)
[@upgrade_src.match?(/load_keys_rc=\$\?/),
 @upgrade_src.match?(/if\s*\[\s*"\$load_keys_rc"\s*-ne\s*0\s*\]/),
 @upgrade_src.match?(/FATAL:\s+Phase\s+3\s+\(load_keys\.rb\)\s+failed/),
 @upgrade_src.match?(/exit\s+"\$load_keys_rc"/)].all?
#=> true

## Functional check: invoking upgrade.sh with a deliberately-broken Phase 3
## input (subdirs present, transformed files absent) propagates exit 1 and
## prints the FATAL line. Skip when Redis is unavailable: upgrade.sh pings
## source/target before reaching Phase 3 and would fail earlier on its own.
if redis_available?
  @propagate_dir = Dir.mktmpdir('load_keys_propagate_')
  stage_input_dir(@propagate_dir, files: { indexes: true })

  @propagate_stdout, @propagate_stderr, @propagate_status = Open3.capture3(
    'bash', UPGRADE_SH,
    '--execute', '--start-phase=3', '--skip-gates',
    "--source-url=#{TEST_VALKEY_URL}",
    "--target-url=#{TEST_VALKEY_URL}",
    "--data-dir=#{@propagate_dir}",
    chdir: PROJECT_ROOT
  )
end

## upgrade.sh exits non-zero when load_keys.rb fails Phase 3.
redis_available? ? (@propagate_status.exitstatus != 0) : true
#=> true

## upgrade.sh prints the FATAL line naming Phase 3 + load_keys.rb.
redis_available? ? @propagate_stdout.include?('FATAL: Phase 3 (load_keys.rb) failed') : true
#=> true

# Teardown for propagation case
FileUtils.rm_rf(@propagate_dir) if defined?(@propagate_dir) && @propagate_dir
