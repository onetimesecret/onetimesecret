# try/migrations/rename_ascii_display_domain_index_try.rb
#
# frozen_string_literal: true

# Tests for migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb
#
# Real-Valkey coverage (no mocks) for the index key rename:
#   - the old key and the runbook's backup key are seeded raw, as a v0.26.17
#     install has them
#   - a dry run changes nothing and counts what it would rename
#   - the run renames both keys, the model reads the entries under the new
#     name, and the migration is no longer needed
#   - a target that already exists refuses that rename and leaves both keys,
#     while the other pair still renames
#   - down renames back, and raises when a destination exists (the runner
#     clears the applied mark whatever down returns)
#
# Run: tests/lanes/run unit --only try/migrations/rename_ascii_display_domain_index_try.rb

require_relative '../support/test_models'
require 'familia/migration'
require_relative '../../migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for ascii_display_domain_index rename migration test run'

MIG = Onetime::Migrations::RenameAsciiDisplayDomainIndex

@index      = Onetime::CustomDomain.ascii_display_domain_index
@client     = @index.dbclient
@new_key    = @index.dbkey
@old_key    = @new_key.sub('ascii_display_domain_index', 'canonical_display_domain_index')
@backup_old = "#{@old_key}:before-backfill"
@backup_new = "#{@new_key}:before-backfill"
@sfx        = SecureRandom.hex(4)
@name_a     = "xn--bcher-kva-#{@sfx}.example"
@name_b     = "plain-#{@sfx}.example"

def migration(run:)
  m = MIG.new(run: run)
  m.prepare
  m
end

## Setup: the keys differ and the new one is the model's index key
[@old_key.include?('canonical_display_domain_index'), @new_key.include?('ascii_display_domain_index'), @old_key == @new_key]
#=> [true, true, false]

## Setup: seed the old key and the runbook backup as a v0.26.17 install has them
@client.hset(@old_key, @name_a, 'id-a')
@client.hset(@old_key, @name_b, 'id-b')
@client.hset(@backup_old, @name_a, 'id-a')
[@client.hlen(@old_key), @client.hlen(@backup_old), @client.exists?(@new_key), @client.exists?(@backup_new)]
#=> [2, 1, false, false]

## The migration is reversible
MIG.new.reversible?
#=> true

## migration_needed? is true while the old key exists
migration(run: false).migration_needed?
#=> true

# --- Dry run ---

## Dry run completes and counts both renames
@dry = migration(run: false)
[@dry.migrate, @dry.stats[:would_rename], @dry.stats[:renamed]]
#=> [true, 2, 0]

## Dry run changes nothing
[@client.hlen(@old_key), @client.hlen(@backup_old), @client.exists?(@new_key), @client.exists?(@backup_new)]
#=> [2, 1, false, false]

# --- Actual run ---

## The run renames the index and the backup
@run = migration(run: true)
[@run.migrate, @run.stats[:renamed]]
#=> [true, 2]

## The entries are under the new key, the old keys are gone
[@client.hlen(@new_key), @client.hlen(@backup_new), @client.exists?(@old_key), @client.exists?(@backup_old)]
#=> [2, 1, false, false]

## The model reads the renamed entries
[@index.get(@name_a), @index.get(@name_b)]
#=> ['id-a', 'id-b']

## migration_needed? is false afterwards
migration(run: false).migration_needed?
#=> false

## A rerun renames nothing and reports both sources absent
@rerun = migration(run: true)
[@rerun.migrate, @rerun.stats[:renamed], @rerun.stats[:absent]]
#=> [true, 0, 2]

# --- Refusal: the target exists ---

## An old key that reappears next to the new one is refused, not merged
@client.hset(@old_key, "late-#{@sfx}.example", 'id-late')
@refused = migration(run: true)
[@refused.migrate, @refused.stats[:refused], @refused.stats[:renamed]]
#=> [false, 1, 0]

## Both keys are left as they were
[@client.hlen(@old_key), @client.hlen(@new_key), @index.get(@name_a)]
#=> [1, 2, 'id-a']

## A refused index rename does not stop the backup rename
@client.del(@backup_new)
@client.hset(@backup_old, @name_b, 'id-b')
@partial = migration(run: true)
[@partial.migrate, @partial.stats[:refused], @partial.stats[:renamed], @client.exists?(@backup_old), @client.hlen(@backup_new)]
#=> [false, 1, 1, false, 1]

## Cleanup the late entry before rolling back
@client.del(@old_key)
@client.exists?(@old_key)
#=> false

# --- Rollback ---

## down renames both keys back
@down = migration(run: true)
[@down.down, @down.stats[:renamed]]
#=> [true, 2]

## The entries are under the old key again
[@client.hlen(@old_key), @client.hlen(@backup_old), @client.exists?(@new_key), @client.exists?(@backup_new), @client.hget(@old_key, @name_a)]
#=> [2, 1, false, false, 'id-a']

## down raises when a destination exists, so the runner keeps the migration applied
@client.hset(@new_key, "late-#{@sfx}.example", 'id-late')
@blocked = migration(run: true)
@raised  = begin
  @blocked.down
  nil
rescue Familia::Migration::Errors::MigrationError => ex
  ex
end
[@raised.class, @blocked.stats[:refused], @blocked.stats[:renamed], @client.hlen(@old_key), @client.hlen(@new_key)]
#=> [Familia::Migration::Errors::MigrationError, 1, 0, 2, 1]

## Teardown
@client.del(@old_key, @backup_old, @new_key)
@client.exists?(@old_key)
#=> false
