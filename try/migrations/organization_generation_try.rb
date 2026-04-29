# try/migrations/organization_generation_try.rb
#
# frozen_string_literal: true

# Tests for scripts/upgrades/v0.24.5/02-organization/{generate,create_indexes,
# validate_instance_index}.rb plus the Organization stage of run_pipeline.sh.
#
# Regression context (#3041): the v0.24.5 upgrade pipeline produced
# Organization records but never emitted OrganizationMembership records, which
# in turn left organization:org_customer_lookup empty. Customers appeared in
# org.members ZSETs and customer.participations SETs, but model-level lookups
# such as OrganizationMembership.find_by_org_customer returned nil. The
# Organization-stage validator also lacked a --redis-url option, so
# run_pipeline.sh:115 invoked it without one (out of step with the customer
# and customdomain validators on lines 106 and 124).
#
# What these tests lock in (post-fix contract):
#   1. generate.rb + create_indexes.rb + load_keys.rb (the production path)
#      produce a discoverable OrganizationMembership for each org's owner with
#      role='owner', status='active', and a positive joined_at.
#   2. organization:org_customer_lookup HSET contains the expected
#      "org_objid:owner_id" -> membership_objid mapping.
#   3. The owner is in org.members (ZSET) and the org collection key is in
#      customer.participations (SET) — guards the existing behavior that the
#      fix must not regress.
#   4. Re-running the pipeline produces no duplicate memberships and leaves
#      the lookup HSET stable.
#   5. validate_instance_index.rb accepts --redis-url=... and exits 0 against
#      the seeded fixture.
#   6. run_pipeline.sh:115 invokes the org validator with --redis-url, mirroring
#      the customer (:106) and customdomain (:124) calls.
#   7. Snippet-A audit (sample N orgs, count missing memberships) reports zero
#      gaps after the fix.
#
# Implementation notes:
#   - Customer fixture records carry real Redis DUMP blobs of v2-serialized
#     hashes — generate.rb RESTOREs and deserialize_v2_fields-decodes the
#     contents. Fake bytes raise Redis::CommandError.
#   - Index commands are applied via load_keys.rb (the production applier)
#     rather than reimplemented; that's the same code path Prod-1's emitter
#     output flows through in production.
#   - Tests boot OT in-process to use OrganizationMembership.find_by_org_customer
#     — the storage shape (additional JSONL records vs index commands vs both)
#     is implementation detail; the contract is the model lookup.
#   - If no test Redis is reachable on port 2121, the whole file exits 0
#     cleanly so CI doesn't false-fail on missing infrastructure.

require_relative '../support/test_helpers'

require 'base64'
require 'fileutils'
require 'json'
require 'open3'
require 'redis'
require 'securerandom'
require 'tmpdir'
require 'uri'

PROJECT_ROOT  = File.expand_path('../..', __dir__).freeze
ORG_DIR       = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/02-organization').freeze
GENERATE_RB   = File.join(ORG_DIR, 'generate.rb').freeze
INDEXES_RB    = File.join(ORG_DIR, 'create_indexes.rb').freeze
VALIDATOR_RB  = File.join(ORG_DIR, 'validate_instance_index.rb').freeze
LOAD_KEYS_RB  = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/load_keys.rb').freeze
PIPELINE_SH   = File.join(PROJECT_ROOT, 'scripts/upgrades/v0.24.5/run_pipeline.sh').freeze

TEST_REDIS_URL = ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:2121/0'
TEMP_DB        = 14  # generate/create_indexes use --temp-db for RESTORE staging
                     # 15 is the script default; keep our value distinct to surface
                     # accidental cross-talk between staging and target databases.

# --- Fixture builders ---------------------------------------------------------

# Stages a v2-serialized customer hash into Redis under a temp key, DUMPs it,
# DELs the key, and returns the base64-encoded DUMP. Mirrors what 01-customer
# transform.rb writes into customer_transformed.jsonl.
def customer_dump_b64(redis, fields)
  temp_key = "_test_customer_stage_#{SecureRandom.hex(6)}"
  serialized = fields.transform_values { |v| v.nil? ? 'null' : JSON.generate(v) }
  redis.hset(temp_key, serialized)
  blob = redis.dump(temp_key)
  redis.del(temp_key)
  Base64.strict_encode64(blob)
end

# Builds a customer_transformed.jsonl record carrying a real DUMP blob.
def customer_record(redis:, objid:, email:, created:, **extra_fields)
  fields = {
    'custid' => objid,
    'email' => email,
    'planid' => extra_fields[:planid] || 'free',
    'created' => created.to_f,
    'updated' => created.to_f,
    'v1_custid' => email,
  }
  fields['stripe_customer_id'] = extra_fields[:stripe_customer_id] if extra_fields[:stripe_customer_id]

  {
    'key' => "customer:#{email}:object",
    'type' => 'hash',
    'ttl_ms' => -1,
    'db' => 0,
    'dump' => customer_dump_b64(redis, fields),
    'objid' => objid,
    'extid' => "ur#{SecureRandom.hex(12).rjust(25, '0')[0, 25]}",
    'created' => created.to_f,
  }
end

def write_jsonl(path, records)
  FileUtils.mkdir_p(File.dirname(path))
  File.open(path, 'w') { |f| records.each { |r| f.puts(JSON.generate(r)) } }
end

def read_jsonl(path)
  File.foreach(path).map { |line| JSON.parse(line.chomp) }
end

# Shells out with VALKEY_URL/REDIS_URL pointing at the test Redis so any
# script that picks them up via env (vs flag) hits the same database.
def shell_out(*cmd)
  env = { 'VALKEY_URL' => TEST_REDIS_URL, 'REDIS_URL' => TEST_REDIS_URL }
  Open3.capture3(env, *cmd, chdir: PROJECT_ROOT)
end

def run_generate(input_file:, output_dir:)
  shell_out('ruby', GENERATE_RB,
            "--input-file=#{input_file}",
            "--output-dir=#{output_dir}",
            "--redis-url=#{TEST_REDIS_URL}",
            "--temp-db=#{TEMP_DB}")
end

def run_create_indexes(input_file:, output_dir:)
  shell_out('ruby', INDEXES_RB,
            "--input-file=#{input_file}",
            "--output-dir=#{output_dir}",
            "--redis-url=#{TEST_REDIS_URL}",
            "--temp-db=#{TEMP_DB}")
end

# Apply only the organization indexes JSONL via load_keys.rb. We skip the
# RESTORE phase because:
#   - the fixture has no on-disk customer_transformed.jsonl in the expected
#     load_keys layout, only an inline path we pass to generate.rb, and
#   - org.members ZSET / customer.participations SET / org_customer_lookup
#     HSET are all populated from index commands, which is what we're testing.
def run_load_keys(input_dir:)
  shell_out('ruby', LOAD_KEYS_RB,
            "--input-dir=#{input_dir}",
            "--valkey-url=#{TEST_REDIS_URL}",
            '--model=organization',
            '--skip-records')
end

# --- Redis availability guard -------------------------------------------------

def redis_reachable?(url)
  client = Redis.new(url: url, timeout: 1.0)
  client.ping == 'PONG'
rescue StandardError
  false
ensure
  client&.close
end

unless redis_reachable?(TEST_REDIS_URL)
  warn "[organization_generation_try] Redis at #{TEST_REDIS_URL} not reachable — skipping."
  exit 0
end

# --- Test setup ---------------------------------------------------------------

OT.boot! :test

@redis = Redis.new(url: TEST_REDIS_URL)
@redis.flushdb
# Also flush the temp DB used by generate/create_indexes for RESTORE staging,
# in case a previous run left orphan keys in DB 14.
temp_uri = URI.parse(TEST_REDIS_URL).tap { |u| u.path = "/#{TEMP_DB}" }
Redis.new(url: temp_uri.to_s).then { |r| r.flushdb; r.close }

@workdir   = Dir.mktmpdir('orggen_try_')
@cust_dir  = File.join(@workdir, 'customer')
@org_dir   = File.join(@workdir, 'organization')
@cust_file = File.join(@cust_dir, 'customer_transformed.jsonl')
@org_file  = File.join(@org_dir,  'organization_transformed.jsonl')
@idx_file  = File.join(@org_dir,  'organization_indexes.jsonl')

@ts        = Familia.now.to_i
@records   = [
  { objid: SecureRandom.uuid_v7, email: "alice_#{@ts}@orggentry.example", created: @ts - 300 },
  { objid: SecureRandom.uuid_v7, email: "bob_#{@ts}@orggentry.example",   created: @ts - 200,
    stripe_customer_id: 'cus_orggentry_bob' },
  { objid: SecureRandom.uuid_v7, email: "carol_#{@ts}@orggentry.example", created: @ts - 100 },
]

write_jsonl(@cust_file, @records.map { |r| customer_record(redis: @redis, **r) })

# --- Pipeline shape: validator must be invoked with --redis-url ---------------

## run_pipeline.sh exists at the expected path
File.exist?(PIPELINE_SH)
#=> true

## run_pipeline.sh invokes the org validator with --redis-url, like its peers
@pipeline_src = File.read(PIPELINE_SH)
@pipeline_src.match?(%r{02-organization/validate_instance_index\.rb.*--redis-url=}m)
#=> true

# --- generate.rb produces organization records --------------------------------

## generate.rb runs successfully against the customer fixture
@gen_stdout, @gen_stderr, @gen_status = run_generate(input_file: @cust_file, output_dir: @org_dir)
[@gen_status.success?, File.exist?(@org_file)]
#=> [true, true]

## generate.rb emits one organization per customer object with required fields
@org_records = read_jsonl(@org_file)
[@org_records.size,
 @org_records.all? { |r| r['key']&.match?(%r{\Aorganization:[0-9a-f-]{36}:object\z}) },
 @org_records.all? { |r| r['objid'] && r['extid']&.start_with?('on') && r['owner_id'] && r['contact_email'] }]
#=> [3, true, true]

## owner_id values exactly match the customer objids the records came from
expected_owners = @records.map { |r| r[:objid] }.sort
@org_records.map { |r| r['owner_id'] }.sort == expected_owners
#=> true

# --- create_indexes.rb + load_keys.rb populates Redis state ------------------

## create_indexes.rb runs successfully and writes the indexes JSONL
@idx_stdout, @idx_stderr, @idx_status = run_create_indexes(input_file: @org_file, output_dir: @org_dir)
[@idx_status.success?, File.exist?(@idx_file)]
#=> [true, true]

## load_keys.rb applies the indexes against the test Redis
@load_stdout, @load_stderr, @load_status = run_load_keys(input_dir: @workdir)
@load_status.success?
#=> true

## organization:instances ZSET contains all generated org_objids
@org_objids = @org_records.map { |r| r['objid'] }
(@org_objids - @redis.zrange('organization:instances', 0, -1)).empty?
#=> true

## For every org, the owner is present in organization:{org}:members (ZSET behavior)
@org_records.all? { |r| @redis.zscore("organization:#{r['objid']}:members", r['owner_id']) }
#=> true

## For every org, customer:{owner}:participations contains the org's members key
@org_records.all? do |r|
  @redis.sismember("customer:#{r['owner_id']}:participations",
                   "organization:#{r['objid']}:members")
end
#=> true

# --- Membership emission contract (#3041 fix) ---------------------------------

## organization:org_customer_lookup HSET contains an entry for every (org, owner) pair
@expected_lookup_keys = @org_records.map { |r| "#{r['objid']}:#{r['owner_id']}" }.sort
@actual_lookup_keys   = @redis.hkeys('organization:org_customer_lookup').sort
(@expected_lookup_keys - @actual_lookup_keys).empty?
#=> true

## OrganizationMembership.find_by_org_customer returns a non-nil membership for every org/owner pair
@memberships = @org_records.map do |r|
  Onetime::OrganizationMembership.find_by_org_customer(r['objid'], r['owner_id'])
end
@memberships.none?(&:nil?)
#=> true

## Each membership has role='owner', status='active', and positive joined_at
@memberships.map { |m| [m.role, m.status, m.joined_at.to_f.positive?] }.uniq
#=> [["owner", "active", true]]

## Each membership has organization_objid and customer_objid pointing at the right pair
@memberships.zip(@org_records).all? do |m, r|
  m.organization_objid == r['objid'] && m.customer_objid == r['owner_id']
end
#=> true

# --- Snippet-A regression check (0429-upgrade-bugs.md) -----------------------

## Sampled audit reports zero (org, owner) pairs missing OrganizationMembership
@sampled_orgs = Onetime::Organization.instances.revrange(0, 19)
@total_pairs   = 0
@missing_pairs = 0
@sampled_orgs.each do |org_objid|
  member_objids = @redis.zrange("organization:#{org_objid}:members", 0, -1)
  next if member_objids.empty?

  member_objids.each do |cust_objid|
    @total_pairs += 1
    @missing_pairs += 1 if Onetime::OrganizationMembership.find_by_org_customer(org_objid, cust_objid).nil?
  end
end
[@total_pairs.positive?, @missing_pairs]
#=> [true, 0]

# --- Idempotency: re-running create_indexes.rb + load_keys.rb is stable -------

## Snapshot membership state before the second pass
@before_lookup_size = @redis.hlen('organization:org_customer_lookup')
@before_membership_objids = @org_records.map do |r|
  Onetime::OrganizationMembership.find_by_org_customer(r['objid'], r['owner_id']).objid
end
@before_lookup_size
#=> 3

## Second create_indexes.rb pass succeeds
run_create_indexes(input_file: @org_file, output_dir: @org_dir).last.success?
#=> true

## Second load_keys.rb pass succeeds
run_load_keys(input_dir: @workdir).last.success?
#=> true

## Lookup HSET size is unchanged (no duplicates)
@redis.hlen('organization:org_customer_lookup') == @before_lookup_size
#=> true

## Each (org, owner) still resolves to the same membership objid
@after_membership_objids = @org_records.map do |r|
  Onetime::OrganizationMembership.find_by_org_customer(r['objid'], r['owner_id']).objid
end
@after_membership_objids == @before_membership_objids
#=> true

# --- Validator CLI: --redis-url is accepted and the run exits 0 ---------------

## validate_instance_index.rb --redis-url=... runs and exits 0
@val_stdout, @val_stderr, @val_status = shell_out(
  'ruby', VALIDATOR_RB,
  "--transformed-file=#{@org_file}",
  "--indexes-file=#{@idx_file}",
  "--customer-file=#{@cust_file}",
  "--redis-url=#{TEST_REDIS_URL}",
)
[@val_status.success?, @val_stderr.include?('Unknown option: --redis-url')]
#=> [true, false]

# --- Teardown ----------------------------------------------------------------

@redis.flushdb
@redis.close
Redis.new(url: temp_uri.to_s).then { |r| r.flushdb; r.close }
FileUtils.rm_rf(@workdir) if @workdir
