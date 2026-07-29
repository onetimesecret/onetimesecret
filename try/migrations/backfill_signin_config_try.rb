# try/migrations/backfill_signin_config_try.rb
#
# frozen_string_literal: true

# Tests for migrations/2026-07-27/20260727_01_backfill_signin_config.rb
#
# Covers (cutoff-guard focus — the fleet-wide-vs-per-ticket attribute
# decision is intentionally out of scope):
#   - an actual run (--run) WITHOUT SIGNIN_BACKFILL_CREATED_BEFORE is
#     REFUSED (returns false -> exit 1) and creates NOTHING — the nil
#     cutoff must never flow into an unbounded enabled-record backfill
#   - dry-run without the cutoff still proceeds (unbounded preview) and
#     mutates nothing
#   - with a cutoff: pre-cutoff domains get the enabled follow-global
#     SigninConfig (all four booleans true), at-or-after-cutoff domains
#     are skipped (:skipped_created_after_cutoff)
#   - existing SigninConfig records are never touched (idempotency)
#   - an unparseable cutoff fails fast in prepare (Onetime::Problem)
#
# Note:
#   CustomDomain.create! stamps `created` at now, so the pre-v0.26 state is
#   staged by overwriting the raw hash field — same technique as
#   backfill_homepage_secrets_mode_try.rb.

require_relative '../support/test_models'
require 'familia/migration'
require_relative '../../migrations/2026-07-27/20260727_01_backfill_signin_config'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for backfill-signin-config migration test run'

ENV.delete('SIGNIN_BACKFILL_CREATED_BEFORE')

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "sc_bf_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("ScBf Test Org #{@ts}", @owner, "sc_bf_#{@ts}@test.com")

# Domain OLD: predates v0.26 (staged past `created` — in backfill scope).
OLD_CREATED_AT = 1_600_000_000
@domain_old = Onetime::CustomDomain.create!("sc-bf-old-#{@ts}.example.com", @org.objid)
Familia.dbclient.hset(@domain_old.dbkey, 'created', OLD_CREATED_AT.to_s)

# Domain NEW: created now — legitimately carries the fail-closed default and
# must be excluded by any cutoff at or before its creation time.
@domain_new = Onetime::CustomDomain.create!("sc-bf-new-#{@ts}.example.com", @org.objid)

@config_class = Onetime::CustomDomain::SigninConfig

## Setup: neither domain has a SigninConfig record
[
  @config_class.exists_for_domain?(@domain_old.identifier),
  @config_class.exists_for_domain?(@domain_new.identifier),
]
#=> [false, false]

# --- Actual run WITHOUT cutoff: refused ---

## --run without SIGNIN_BACKFILL_CREATED_BEFORE returns false (exit 1)
@refused = Onetime::Migrations::BackfillSigninConfig.new(run: true)
@refused.prepare
@refused.migrate
#=> false

## The refused run created NOTHING for either domain and tracked no stats
[
  @config_class.exists_for_domain?(@domain_old.identifier),
  @config_class.exists_for_domain?(@domain_new.identifier),
  @refused.stats[:created],
]
#=> [false, false, 0]

# --- Dry run WITHOUT cutoff: unbounded preview, proceeds, mutates nothing ---

## Dry run without the cutoff still completes (preview-only escape hatch)
@dry = Onetime::Migrations::BackfillSigninConfig.new(run: false)
@dry.prepare
@dry.migrate
#=> true

## The unbounded preview puts BOTH domains in scope but writes nothing
[
  @dry.stats[:would_create],
  @config_class.exists_for_domain?(@domain_old.identifier),
  @config_class.exists_for_domain?(@domain_new.identifier),
]
#=> [2, false, false]

# --- Actual run WITH cutoff: old backfilled, new skipped ---

## With a cutoff between the two domains' created stamps, the run applies
ENV['SIGNIN_BACKFILL_CREATED_BEFORE'] = (@ts - 100).to_s
@run = Onetime::Migrations::BackfillSigninConfig.new(run: true)
@run.prepare
@run.migrate
#=> true

## Pre-cutoff domain got the record; at-or-after-cutoff domain was skipped
[
  @run.stats[:created],
  @run.stats[:skipped_created_after_cutoff],
  @config_class.exists_for_domain?(@domain_old.identifier),
  @config_class.exists_for_domain?(@domain_new.identifier),
]
#=> [1, 1, true, false]

## The backfilled record carries the follow-global attribute set (all four
## booleans true, no restrict_to) — the exact pre-v0.26 resolution
cfg = @config_class.find_by_domain_id(@domain_old.identifier)
[cfg.enabled?, cfg.signin_enabled?, cfg.email_auth_enabled?, cfg.sso_enabled?, cfg.restrict_to.to_s]
#=> [true, true, true, true, '']

# --- Idempotency: existing records are never touched ---

## Re-running with the same cutoff skips the existing record
@rerun = Onetime::Migrations::BackfillSigninConfig.new(run: true)
@rerun.prepare
@rerun.migrate
[@rerun.stats[:created], @rerun.stats[:skipped_existing], @rerun.stats[:errors]]
#=> [0, 1, 0]

# --- Unparseable cutoff fails fast in prepare ---

## An unparseable SIGNIN_BACKFILL_CREATED_BEFORE raises Onetime::Problem
ENV['SIGNIN_BACKFILL_CREATED_BEFORE'] = 'not-a-time'
@bad = Onetime::Migrations::BackfillSigninConfig.new(run: true)
begin
  @bad.prepare
  'no raise'
rescue Onetime::Problem => ex
  ex.message.include?('SIGNIN_BACKFILL_CREATED_BEFORE is not parseable')
end
#=> true

# Teardown
ENV.delete('SIGNIN_BACKFILL_CREATED_BEFORE')
Familia.dbclient.flushdb
