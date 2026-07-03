# try/migrations/backfill_homepage_secrets_mode_try.rb
#
# frozen_string_literal: true

# Tests for migrations/2026-07-03/20260703_02_backfill_homepage_secrets_mode.rb
#
# Covers:
#   - migration_needed? is true while any HomepageConfig lacks a recognised
#     stored secrets_mode
#   - dry-run performs no writes and reports would_backfill / already_set
#   - actual run persists secrets_mode='create' on legacy records, leaves
#     already-set records untouched (including 'incoming'), and preserves
#     the homepage `enabled` flag
#   - re-running is idempotent (all domains reported as already_set)
#   - domains without a HomepageConfig record are skipped
#
# Note:
#   CustomDomain.create! bootstraps a HomepageConfig that already carries an
#   explicit secrets_mode='create', so the legacy (field-absent) state this
#   migration backfills must be staged by deleting the hash field directly —
#   exactly what a pre-secrets_mode record looks like in Redis.

require_relative '../support/test_models'
require 'familia/migration'
require_relative '../../migrations/2026-07-03/20260703_02_backfill_homepage_secrets_mode'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for backfill-homepage-secrets-mode migration test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_sm_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpSm Test Org #{@ts}", @owner, "hp_sm_#{@ts}@test.com")

# Domain LEGACY: enabled homepage whose record pre-dates the secrets_mode field.
@domain_legacy = Onetime::CustomDomain.create!("hp-sm-legacy-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain_legacy.identifier, enabled: true)
@legacy_cfg = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier)
Familia.dbclient.hdel(@legacy_cfg.dbkey, 'secrets_mode')

# Domain STRAY: carries an unrecognised stored value (corrupt/ancient write).
# Familia JSON-serializes hash field values, so stage a JSON-encoded string.
@domain_stray = Onetime::CustomDomain.create!("hp-sm-stray-#{@ts}.example.com", @org.objid)
@stray_cfg = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_stray.identifier)
Familia.dbclient.hset(@stray_cfg.dbkey, 'secrets_mode', '"bogus"')

# Domain SET: already carries an explicit 'incoming' (must NOT be reset).
@domain_incoming = Onetime::CustomDomain.create!("hp-sm-incoming-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.upsert(
  domain_id: @domain_incoming.identifier, enabled: true, secrets_mode: 'incoming'
)

# Domain DEFAULT: bootstrap record from create! (already carries 'create').
@domain_default = Onetime::CustomDomain.create!("hp-sm-default-#{@ts}.example.com", @org.objid)

## Setup: staged raw secrets_mode states are nil / bogus / incoming / create
[
  Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier).secrets_mode,
  Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_stray.identifier).secrets_mode,
  Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_incoming.identifier).secrets_mode,
  Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_default.identifier).secrets_mode,
]
#=> [nil, 'bogus', 'incoming', 'create']

## migration_needed? is true before any run (legacy + stray lack a recognised mode)
@migration = Onetime::Migrations::BackfillHomepageSecretsMode.new
@migration.prepare
@migration.migration_needed?
#=> true

# --- Dry run ---

## Dry run completes successfully
@dry = Onetime::Migrations::BackfillHomepageSecretsMode.new(run: false)
@dry.prepare
@dry.migrate
#=> true

## Dry run leaves the legacy domain untouched (raw field still absent)
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier).secrets_mode
#=> nil

## Dry run reports the legacy + stray domains under would_backfill
@dry.stats[:would_backfill]
#=> 2

## Dry run reports the incoming + default domains under already_set
@dry.stats[:already_set]
#=> 2

## Dry run performs no writes and reports zero errors
[@dry.stats[:backfilled], @dry.stats[:errors]]
#=> [0, 0]

# --- Actual run ---

## Setup: capture the legacy domain's updated timestamp before the run
@legacy_updated_before = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier).updated.to_i
@legacy_updated_before > 0
#=> true

## Actual run completes successfully
@run = Onetime::Migrations::BackfillHomepageSecretsMode.new(run: true)
@run.prepare
@run.migrate
#=> true

## Legacy domain now carries the explicit 'create' default
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier).secrets_mode
#=> 'create'

## Backfill does not advance the updated timestamp (not a semantic change)
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier).updated.to_i == @legacy_updated_before
#=> true

## Stray value was normalised to 'create'
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_stray.identifier).secrets_mode
#=> 'create'

## Explicit 'incoming' selection is preserved, not reset
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_incoming.identifier).secrets_mode
#=> 'incoming'

## The homepage `enabled` flag on the legacy domain is preserved, not touched
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_legacy.identifier).enabled?
#=> true

## Actual run counts: two backfilled, two already_set, zero errors
[@run.stats[:backfilled], @run.stats[:already_set], @run.stats[:errors]]
#=> [2, 2, 0]

# --- Idempotency ---

## After apply, migration_needed? returns false
@check = Onetime::Migrations::BackfillHomepageSecretsMode.new
@check.prepare
@check.migration_needed?
#=> false

## Re-running reports all four domains as already_set with no writes
@rerun = Onetime::Migrations::BackfillHomepageSecretsMode.new(run: true)
@rerun.prepare
@rerun.migrate
[@rerun.stats[:already_set], @rerun.stats[:backfilled], @rerun.stats[:errors]]
#=> [4, 0, 0]

# --- Missing HomepageConfig is skipped ---

## Setup: a domain whose HomepageConfig record has been removed
@domain_nocfg = Onetime::CustomDomain.create!("hp-sm-nocfg-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@domain_nocfg.identifier)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_nocfg.identifier)
#=> false

## migrate skips the record-less domain and still reports no errors
@skip_run = Onetime::Migrations::BackfillHomepageSecretsMode.new(run: true)
@skip_run.prepare
@skip_run.migrate
[@skip_run.stats[:skipped_missing_config], @skip_run.stats[:errors]]
#=> [1, 0]

# --- Empty instances set ---

## Setup: flush Redis so CustomDomain.instances is empty
Familia.dbclient.flushdb
Onetime::CustomDomain.instances.to_a
#=> []

## migration_needed? is false with zero domains
@empty_check = Onetime::Migrations::BackfillHomepageSecretsMode.new
@empty_check.prepare
@empty_check.migration_needed?
#=> false

## migrate returns true without raising and writes nothing
@empty_run = Onetime::Migrations::BackfillHomepageSecretsMode.new(run: true)
@empty_run.prepare
@empty_run.migrate
[@empty_run.stats[:backfilled], @empty_run.stats[:already_set], @empty_run.stats[:errors]]
#=> [0, 0, 0]

# Teardown
Familia.dbclient.flushdb
