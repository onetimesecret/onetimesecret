# try/migrations/homepage_config_backfill_try.rb
#
# frozen_string_literal: true

# Tests for migrations/2026-04-17/20260417_01_backfill_homepage_config.rb
#
# Covers:
#   - migration_needed? is true when a domain has legacy
#     brand_settings.allow_public_homepage but no HomepageConfig record
#   - dry-run performs no writes
#   - actual run creates HomepageConfig with enabled=true for legacy-on domains,
#     enabled=false for legacy-off domains, and leaves pre-existing records alone
#   - re-running is idempotent (all domains reported as skipped_existing)

require_relative '../support/test_models'
require 'familia/migration'
require_relative '../../migrations/2026-04-17/20260417_01_backfill_homepage_config'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for HomepageConfig backfill migration test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_bf_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpBf Test Org #{@ts}", @owner, "hp_bf_#{@ts}@test.com")

# Domain A: legacy allow_public_homepage = true, no HomepageConfig yet.
@domain_on                                = Onetime::CustomDomain.create!("hp-bf-on-#{@ts}.example.com", @org.objid)
@domain_on.brand['allow_public_homepage'] = true
@domain_on.instance_variable_set(:@brand_settings, nil)

# Domain B: legacy allow_public_homepage = false, no HomepageConfig yet.
@domain_off                                = Onetime::CustomDomain.create!("hp-bf-off-#{@ts}.example.com", @org.objid)
@domain_off.brand['allow_public_homepage'] = false
@domain_off.instance_variable_set(:@brand_settings, nil)

# Domain C: pre-existing HomepageConfig(enabled=true), legacy value false.
# The migration must not overwrite this record.
@domain_pre                                = Onetime::CustomDomain.create!("hp-bf-pre-#{@ts}.example.com", @org.objid)
@domain_pre.brand['allow_public_homepage'] = false
@domain_pre.instance_variable_set(:@brand_settings, nil)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain_pre.identifier, enabled: true)

## Setup: brand_settings reflects the staged values
[@domain_on.brand_settings.allow_public_homepage?,
 @domain_off.brand_settings.allow_public_homepage?,
 @domain_pre.brand_settings.allow_public_homepage?]
#=> [true, false, false]

## Setup: only the pre-existing domain starts with a HomepageConfig
[Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_on.identifier),
 Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_off.identifier),
 Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_pre.identifier)]
#=> [false, false, true]

## migration_needed? is true before any run
@migration = Onetime::Migrations::BackfillHomepageConfig.new
@migration.prepare
@migration.migration_needed?
#=> true

# --- Dry run ---

## Dry run completes successfully
@dry = Onetime::Migrations::BackfillHomepageConfig.new(run: false)
@dry.prepare
@dry.migrate
#=> true

## Dry run records no writes for the on-domain
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_on.identifier)
#=> false

## Dry run records no writes for the off-domain
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_off.identifier)
#=> false

## Dry run reports both unmigrated domains under would_migrate_*
[@dry.stats[:would_migrate_true], @dry.stats[:would_migrate_false]]
#=> [1, 1]

## Dry run skips the pre-existing record
@dry.stats[:skipped_existing]
#=> 1

## Dry run performs no writes and reports zero errors
[@dry.stats[:migrated_true], @dry.stats[:migrated_false], @dry.stats[:errors]]
#=> [0, 0, 0]

# --- Actual run ---

## Actual run completes successfully
@run = Onetime::Migrations::BackfillHomepageConfig.new(run: true)
@run.prepare
@run.migrate
#=> true

## On-domain now has HomepageConfig(enabled=true)
@cfg_on = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_on.identifier)
@cfg_on.enabled?
#=> true

## Off-domain now has HomepageConfig(enabled=false)
@cfg_off = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_off.identifier)
@cfg_off.enabled?
#=> false

## Pre-existing HomepageConfig is untouched (still enabled=true)
@cfg_pre = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_pre.identifier)
@cfg_pre.enabled?
#=> true

## Actual run counts match: one true, one false migrated, one skipped
[@run.stats[:migrated_true], @run.stats[:migrated_false], @run.stats[:skipped_existing], @run.stats[:errors]]
#=> [1, 1, 1, 0]

# --- Idempotency ---

## After apply, migration_needed? returns false
@check = Onetime::Migrations::BackfillHomepageConfig.new
@check.prepare
@check.migration_needed?
#=> false

## Re-running records all three domains as skipped_existing with no writes
@rerun = Onetime::Migrations::BackfillHomepageConfig.new(run: true)
@rerun.prepare
@rerun.migrate
[@rerun.stats[:skipped_existing], @rerun.stats[:migrated_true], @rerun.stats[:migrated_false], @rerun.stats[:errors]]
#=> [3, 0, 0, 0]

# --- Error path: per-domain rescue in migrate ---
#
# One domain is rigged so that CustomDomain.find_by_identifier raises for it.
# The migration must count :errors, keep processing the remaining domains,
# and must not raise out of migrate.
# Bare code between ## blocks does not execute in Tryouts; we wrap setup in
# explicit setup testcases so @ivars propagate.

## Setup: flush Redis and stage raising + non-raising domain fixtures
Familia.dbclient.flushdb
@ts_err       = Familia.now.to_i
@owner_err    = Onetime::Customer.create!(email: "hp_err_owner_#{@ts_err}_#{SecureRandom.hex(4)}@test.com")
@org_err      = Onetime::Organization.create!("HpErr Test Org #{@ts_err}", @owner_err, "hp_err_#{@ts_err}@test.com")
@domain_err                                = Onetime::CustomDomain.create!("hp-err-raise-#{@ts_err}.example.com", @org_err.objid)
@domain_err.brand['allow_public_homepage'] = true
@domain_err.instance_variable_set(:@brand_settings, nil)
@domain_ok                                 = Onetime::CustomDomain.create!("hp-err-ok-#{@ts_err}.example.com", @org_err.objid)
@domain_ok.brand['allow_public_homepage']  = false
@domain_ok.instance_variable_set(:@brand_settings, nil)
@raising_id                                = @domain_err.identifier
[@raising_id.to_s.length.positive?, @domain_ok.identifier.to_s.length.positive?]
#=> [true, true]

## Setup: install singleton override that raises for one specific id
# Capture closure variables (define_singleton_method's block runs with self bound
# to the class; instance variables inside the block would resolve against the
# class, not this test context).
@original_find      = Onetime::CustomDomain.method(:find_by_identifier)
Onetime::CustomDomain.singleton_class.send(:alias_method, :__orig_find_for_test, :find_by_identifier)
captured_raising_id = @raising_id
Onetime::CustomDomain.define_singleton_method(:find_by_identifier) do |id|
  raise StandardError, "simulated failure for #{id}" if id == captured_raising_id

  __orig_find_for_test(id)
end
# Sanity: routes raising id to StandardError, non-raising id to a real domain
sanity =
  begin
    Onetime::CustomDomain.find_by_identifier(@raising_id)
    :no_raise
  rescue StandardError
    :raised
  end
ok_domain = Onetime::CustomDomain.find_by_identifier(@domain_ok.identifier)
[sanity, ok_domain&.identifier == @domain_ok.identifier]
#=> [:raised, true]

## Error run completes without raising
@err_run = Onetime::Migrations::BackfillHomepageConfig.new(run: true)
@err_run.prepare
@err_run.migrate
#=> true

## Error count is at least one
@err_run.stats[:errors] >= 1
#=> true

## Non-raising domain still received its HomepageConfig
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_ok.identifier)
#=> true

## Non-raising domain's HomepageConfig reflects the legacy value (false)
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_ok.identifier).enabled?
#=> false

## Raising domain did not get a HomepageConfig written
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@raising_id)
#=> false

## Teardown: remove the singleton override so the class method is restored
Onetime::CustomDomain.singleton_class.send(:remove_method, :find_by_identifier)
Onetime::CustomDomain.singleton_class.send(:remove_method, :__orig_find_for_test)
Onetime::CustomDomain.find_by_identifier(@domain_ok.identifier).identifier == @domain_ok.identifier
#=> true

# --- migration_needed? false when all domains already have HomepageConfig ---

## Setup: flush and stage two domains that already have HomepageConfigs
Familia.dbclient.flushdb
@ts_pre    = Familia.now.to_i
@owner_pre = Onetime::Customer.create!(email: "hp_pre_owner_#{@ts_pre}_#{SecureRandom.hex(4)}@test.com")
@org_pre   = Onetime::Organization.create!("HpPre Test Org #{@ts_pre}", @owner_pre, "hp_pre_#{@ts_pre}@test.com")
@domain_p1 = Onetime::CustomDomain.create!("hp-pre-1-#{@ts_pre}.example.com", @org_pre.objid)
@domain_p2 = Onetime::CustomDomain.create!("hp-pre-2-#{@ts_pre}.example.com", @org_pre.objid)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain_p1.identifier, enabled: true)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain_p2.identifier, enabled: false)
[Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_p1.identifier),
 Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_p2.identifier)]
#=> [true, true]

## needed_false_all_preexisting: every domain already has a config
@pre_check = Onetime::Migrations::BackfillHomepageConfig.new
@pre_check.prepare
@pre_check.migration_needed?
#=> false

# --- Missing brand field defaults to disabled ---

## Setup: flush and stage a domain with no allow_public_homepage brand key
Familia.dbclient.flushdb
@ts_def     = Familia.now.to_i
@owner_def  = Onetime::Customer.create!(email: "hp_def_owner_#{@ts_def}_#{SecureRandom.hex(4)}@test.com")
@org_def    = Onetime::Organization.create!("HpDef Test Org #{@ts_def}", @owner_def, "hp_def_#{@ts_def}@test.com")
@domain_def = Onetime::CustomDomain.create!("hp-def-#{@ts_def}.example.com", @org_def.objid)
@domain_def.brand.delete('allow_public_homepage') if @domain_def.brand.key?('allow_public_homepage')
@domain_def.instance_variable_set(:@brand_settings, nil)
@domain_def.brand.key?('allow_public_homepage')
#=> false

## BrandSettings::DEFAULTS yields false for missing allow_public_homepage
@domain_def.brand_settings.allow_public_homepage?
#=> false

## Migration still reports needed (any domain without HomepageConfig qualifies)
@def_check = Onetime::Migrations::BackfillHomepageConfig.new
@def_check.prepare
@def_check.migration_needed?
#=> true

## missing_brand_setting_defaults_false: after migrate HomepageConfig exists and is disabled
@def_run = Onetime::Migrations::BackfillHomepageConfig.new(run: true)
@def_run.prepare
@def_run.migrate
@def_cfg = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_def.identifier)
[@def_cfg.nil?, @def_cfg&.enabled?]
#=> [false, false]

## Stats reflect one false-valued migration
@def_run.stats[:migrated_false]
#=> 1

# --- Empty instances set ---

## Setup: flush Redis so CustomDomain.instances is empty
Familia.dbclient.flushdb
Onetime::CustomDomain.instances.to_a
#=> []

## empty_instances_set: migration_needed? is false with zero domains
@empty_check = Onetime::Migrations::BackfillHomepageConfig.new
@empty_check.prepare
@empty_check.migration_needed?
#=> false

## empty_instances_set: migrate returns true without raising and writes nothing
@empty_run = Onetime::Migrations::BackfillHomepageConfig.new(run: true)
@empty_run.prepare
@empty_run.migrate
#=> true

## empty_instances_set: all counters are zero
[@empty_run.stats[:migrated_true], @empty_run.stats[:migrated_false],
 @empty_run.stats[:skipped_existing], @empty_run.stats[:errors]]
#=> [0, 0, 0, 0]

# Teardown
Familia.dbclient.flushdb
