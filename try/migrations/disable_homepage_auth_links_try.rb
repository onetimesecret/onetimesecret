# try/migrations/disable_homepage_auth_links_try.rb
#
# frozen_string_literal: true

# Tests for migrations/2026-07-03/20260703_01_disable_homepage_auth_links.rb
#
# Covers:
#   - migration_needed? is true while any HomepageConfig still reports an
#     enabled signup or signin link
#   - dry-run performs no writes and reports would_disable / already_off
#   - actual run flips signup_enabled/signin_enabled true -> false, leaves
#     already-off records untouched, and preserves the homepage `enabled` flag
#   - re-running is idempotent (all domains reported as already_off)
#   - domains without a HomepageConfig record are skipped
#
# Post-#3026 note:
#   - CustomDomain.create! now bootstraps a HomepageConfig with both auth-link
#     toggles OFF (the new conservative default), so the "links enabled" state
#     this migration resets must be staged explicitly via upsert.

require_relative '../support/test_models'
require 'familia/migration'
require_relative '../../migrations/2026-07-03/20260703_01_disable_homepage_auth_links'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for disable-homepage-auth-links migration test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_dis_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpDis Test Org #{@ts}", @owner, "hp_dis_#{@ts}@test.com")

# Domain ON: both auth links enabled (simulates the historical persisted true).
@domain_on = Onetime::CustomDomain.create!("hp-dis-on-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.upsert(
  domain_id: @domain_on.identifier, enabled: true, signup_enabled: true, signin_enabled: true
)

# Domain MIXED: signup on, signin off.
@domain_mixed = Onetime::CustomDomain.create!("hp-dis-mixed-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.upsert(
  domain_id: @domain_mixed.identifier, enabled: true, signup_enabled: true, signin_enabled: false
)

# Domain OFF: both already off (the bootstrap default created by create!).
@domain_off = Onetime::CustomDomain.create!("hp-dis-off-#{@ts}.example.com", @org.objid)

## Setup: staged auth-link states are on / mixed / off
[
  [Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_on.identifier).signup_enabled?,
   Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_on.identifier).signin_enabled?],
  [Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_mixed.identifier).signup_enabled?,
   Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_mixed.identifier).signin_enabled?],
  [Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_off.identifier).signup_enabled?,
   Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_off.identifier).signin_enabled?],
]
#=> [[true, true], [true, false], [false, false]]

## migration_needed? is true before any run (on + mixed have enabled links)
@migration = Onetime::Migrations::DisableHomepageAuthLinks.new
@migration.prepare
@migration.migration_needed?
#=> true

# --- Dry run ---

## Dry run completes successfully
@dry = Onetime::Migrations::DisableHomepageAuthLinks.new(run: false)
@dry.prepare
@dry.migrate
#=> true

## Dry run leaves the on-domain untouched (still enabled)
[Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_on.identifier).signup_enabled?,
 Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_on.identifier).signin_enabled?]
#=> [true, true]

## Dry run reports the on + mixed domains under would_disable
@dry.stats[:would_disable]
#=> 2

## Dry run reports the already-off domain under already_off
@dry.stats[:already_off]
#=> 1

## Dry run performs no writes and reports zero errors
[@dry.stats[:disabled], @dry.stats[:errors]]
#=> [0, 0]

# --- Actual run ---

## Actual run completes successfully
@run = Onetime::Migrations::DisableHomepageAuthLinks.new(run: true)
@run.prepare
@run.migrate
#=> true

## On-domain now has both auth links disabled
@cfg_on = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_on.identifier)
[@cfg_on.signup_enabled?, @cfg_on.signin_enabled?]
#=> [false, false]

## Mixed-domain now has both auth links disabled
@cfg_mixed = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_mixed.identifier)
[@cfg_mixed.signup_enabled?, @cfg_mixed.signin_enabled?]
#=> [false, false]

## Already-off domain is unchanged (still off)
@cfg_off = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_off.identifier)
[@cfg_off.signup_enabled?, @cfg_off.signin_enabled?]
#=> [false, false]

## The homepage `enabled` (public secret form) flag is preserved, not touched
@cfg_on.enabled?
#=> true

## Actual run counts: two disabled, one already_off, zero errors
[@run.stats[:disabled], @run.stats[:already_off], @run.stats[:errors]]
#=> [2, 1, 0]

# --- Idempotency ---

## After apply, migration_needed? returns false
@check = Onetime::Migrations::DisableHomepageAuthLinks.new
@check.prepare
@check.migration_needed?
#=> false

## Re-running reports all three domains as already_off with no writes
@rerun = Onetime::Migrations::DisableHomepageAuthLinks.new(run: true)
@rerun.prepare
@rerun.migrate
[@rerun.stats[:already_off], @rerun.stats[:disabled], @rerun.stats[:errors]]
#=> [3, 0, 0]

# --- Missing HomepageConfig is skipped ---

## Setup: a domain whose HomepageConfig record has been removed
@domain_nocfg = Onetime::CustomDomain.create!("hp-dis-nocfg-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@domain_nocfg.identifier)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_nocfg.identifier)
#=> false

## migrate skips the record-less domain and still reports no errors
@skip_run = Onetime::Migrations::DisableHomepageAuthLinks.new(run: true)
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
@empty_check = Onetime::Migrations::DisableHomepageAuthLinks.new
@empty_check.prepare
@empty_check.migration_needed?
#=> false

## migrate returns true without raising and writes nothing
@empty_run = Onetime::Migrations::DisableHomepageAuthLinks.new(run: true)
@empty_run.prepare
@empty_run.migrate
[@empty_run.stats[:disabled], @empty_run.stats[:already_off], @empty_run.stats[:errors]]
#=> [0, 0, 0]

# Teardown
Familia.dbclient.flushdb
