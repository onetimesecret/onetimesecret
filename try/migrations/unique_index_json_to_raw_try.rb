# try/migrations/unique_index_json_to_raw_try.rb
#
# frozen_string_literal: true

# Tests for migrations/2026-06-06/20260606_01_unique_index_json_to_raw.rb
#
# Real-Redis coverage (no mocks) for the Familia 2.9 -> 2.10 unique_index
# storage-format migration:
#   - a freshly created domain stores its id raw (2.10), so nothing is stale
#   - legacy JSON-encoded data is detected by Familia.stale_indexes (class-level)
#     and by the migration's SCAN of org-scoped email_index keys
#   - the 2.10.1 read path SELF-HEALS: from_display_domain still resolves on
#     stale data (it strips on read) but leaves storage legacy — which is why
#     the boot guard keeps flagging it and the migration is still needed
#   - dry run performs no writes; actual run rewrites legacy -> raw
#   - already-raw entries are left untouched and the run is idempotent
#   - the CheckUniqueIndexFormat boot guard is non-fatal in both states
#
# Notes:
#   - The class-level path uses the real CustomDomain.display_domain_index that
#     backs CustomDomain.from_display_domain (the finder named in #3347).
#   - The org-scoped path seeds organization:<id>:email_index directly, the same
#     direct-redis fixture style the homepage_config tryout uses for corruption.
#     The migration doesn't care how the key got there, only that SCAN finds it.

require_relative '../support/test_models'
require 'json'
require 'familia/migration'
require_relative '../../migrations/2026-06-06/20260606_01_unique_index_json_to_raw'
require_relative '../../lib/onetime/initializers/check_unique_index_format'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for unique_index JSON->raw migration test run'

MIG = Onetime::Migrations::UniqueIndexJsonToRaw

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "uijr_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("UIJR Org #{@ts}", @owner, "uijr_#{@ts}@test.com")
@domain  = "uijr-#{@ts}.example.com"
@cd      = Onetime::CustomDomain.create!(@domain, @org.objid)

@idx        = Onetime::CustomDomain.display_domain_index
@idx_key    = @idx.dbkey
@client     = @idx.dbclient
@org_client = Onetime::Organization.dbclient
@scoped_key = "organization:#{@org.objid}:email_index"
@scoped_fld = "legacy_#{@ts}@example.com"

## Setup: a freshly created domain stores its id raw (Familia 2.10)
@client.hget(@idx_key, @domain) == @cd.identifier
#=> true

## Setup: with only raw data present, no class-level index is stale
Familia.stale_indexes.empty?
#=> true

## Setup: from_display_domain resolves the record on raw data
Onetime::CustomDomain.from_display_domain(@domain)&.identifier == @cd.identifier
#=> true

# --- Simulate legacy Familia 2.9 data ---

## Corrupt the class-level index value to the JSON-encoded 2.9 form
@client.hset(@idx_key, @domain, JSON.dump(@cd.identifier))
Familia.legacy_json_encoded?(@client.hget(@idx_key, @domain))
#=> true

## Seed a legacy entry in the org-scoped email index (SCAN-discovered)
@org_client.hset(@scoped_key, @scoped_fld, JSON.dump('cust_legacy'))
Familia.legacy_json_encoded?(@org_client.hget(@scoped_key, @scoped_fld))
#=> true

## Introspection flags CustomDomain's display_domain_index as stale
Familia.stale_indexes.any? { |d| d.owner == Onetime::CustomDomain && d.index_name == :display_domain_index }
#=> true

## Boot guard (assert_indexes_current!) reports stale without raising
Familia.assert_indexes_current!(on_stale: :warn)
#=> false

## 2.10.1 read path self-heals: the finder still resolves despite stale storage
Onetime::CustomDomain.from_display_domain(@domain)&.identifier == @cd.identifier
#=> true

## ...but the self-heal does not rewrite storage; it stays legacy
Familia.legacy_json_encoded?(@client.hget(@idx_key, @domain))
#=> true

# --- migration_needed? ---

## migration_needed? is true while legacy data exists
@m = MIG.new
@m.prepare
@m.migration_needed?
#=> true

# --- Dry run ---

## Dry run completes successfully
@dry = MIG.new(run: false)
@dry.prepare
@dry.migrate
#=> true

## Dry run performs no writes: class-level value still legacy
Familia.legacy_json_encoded?(@client.hget(@idx_key, @domain))
#=> true

## Dry run performs no writes: scoped value still legacy
Familia.legacy_json_encoded?(@org_client.hget(@scoped_key, @scoped_fld))
#=> true

## Dry run counts the two legacy entries it would convert (1 class + 1 scoped)
@dry.stats[:entries_converted]
#=> 2

# --- Actual run ---

## Actual run completes successfully
@run = MIG.new(run: true)
@run.prepare
@run.migrate
#=> true

## Class-level index value is now raw
@client.hget(@idx_key, @domain) == @cd.identifier
#=> true

## Scoped index value is now raw
@org_client.hget(@scoped_key, @scoped_fld) == 'cust_legacy'
#=> true

## Two entries converted
@run.stats[:entries_converted]
#=> 2

## Introspection is clean after conversion
Familia.stale_indexes.empty?
#=> true

## Boot guard passes (raise mode) once indexes are current
Familia.assert_indexes_current!(on_stale: :raise)
#=> true

## Finder still resolves (now from raw storage, no read-time self-heal)
Onetime::CustomDomain.from_display_domain(@domain)&.identifier == @cd.identifier
#=> true

# --- Idempotency ---

## After conversion, migration_needed? is false
@check = MIG.new
@check.prepare
@check.migration_needed?
#=> false

## Re-running converts nothing
@rerun = MIG.new(run: true)
@rerun.prepare
@rerun.migrate
@rerun.stats[:entries_converted]
#=> 0

# --- Boot initializer (CheckUniqueIndexFormat) ---

## The boot guard runs without raising when indexes are current
@init = Onetime::Initializers::CheckUniqueIndexFormat.new
@init.execute(nil)
:ok
#=> :ok

## The boot guard is non-fatal even when an index is stale (re-seed, then run)
@org_client.hset(@scoped_key, @scoped_fld, JSON.dump('cust_legacy'))
@client.hset(@idx_key, @domain, JSON.dump(@cd.identifier))
@init.execute(nil)
:ok
#=> :ok

# --- Metadata ---

## migration_id is stable
MIG.migration_id
#=> '20260606_01_unique_index_json_to_raw'

## no dependencies
MIG.dependencies
#=> []

# Cleanup
## Cleanup: flush the test database
Familia.dbclient.flushdb
#=> "OK"
