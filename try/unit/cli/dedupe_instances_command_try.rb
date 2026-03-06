# try/unit/cli/dedupe_instances_command_try.rb
#
# frozen_string_literal: true

# Integration tests for DedupeInstancesCommand that exercise sorted set
# and set deduplication/normalization against a real Redis instance.
#
# Requires the test Redis on port 2121 (pnpm run test:database:start).
#
# Run: bundle exec try try/unit/cli/dedupe_instances_command_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

# Setup: use isolated test keys so we don't collide with real data
@redis = Familia.dbclient
@zset_key = 'test:dedupe_instances:zset'
@set_key  = 'test:dedupe_instances:set'

# Clean up before starting
@redis.del(@zset_key, @set_key)

# Build a command instance to test private methods via send
@cmd = Onetime::CLI::DedupeInstancesCommand.new

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## DedupeInstancesCommand exists and inherits from Command
Onetime::CLI::DedupeInstancesCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## DedupeInstancesCommand includes DeduplicationHelper
Onetime::CLI::DedupeInstancesCommand.ancestors.include?(Onetime::CLI::DeduplicationHelper)
#=> true

## DedupeInstancesCommand can be instantiated
@cmd.is_a?(Dry::CLI::Command)
#=> true

# -------------------------------------------------------------------
# Sorted set deduplication (zrem only): both raw and quoted exist
# -------------------------------------------------------------------

## Setup sorted set with raw + quoted duplicates
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'abc')
@redis.zadd(@zset_key, 2.0, '"abc"')
@redis.zadd(@zset_key, 3.0, 'def')
@redis.zadd(@zset_key, 4.0, '"def"')
@redis.zadd(@zset_key, 5.0, 'ghi')
@redis.zcard(@zset_key)
#=> 5

## Dry-run sorted set dedup: no changes made
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-zset', @zset_key, stats, true, false)
[@redis.zcard(@zset_key), stats[:duplicates_removed]]
#=> [5, 2]

## Run-mode sorted set dedup: quoted duplicates removed
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-zset', @zset_key, stats, false, false)
[@redis.zcard(@zset_key), stats[:duplicates_removed]]
#=> [3, 2]

## After dedup, only raw members remain
remaining = @redis.zrange(@zset_key, 0, -1).sort
remaining
#=> ["abc", "def", "ghi"]

# -------------------------------------------------------------------
# Sorted set with only quoted members (no raw counterpart)
# The normalization case -- quoted members should be unquoted
# -------------------------------------------------------------------

## Setup sorted set with orphan quoted members only
@redis.del(@zset_key)
@redis.zadd(@zset_key, 10.0, '"orphan1"')
@redis.zadd(@zset_key, 20.0, '"orphan2"')
@redis.zadd(@zset_key, 30.0, 'raw_only')
@redis.zcard(@zset_key)
#=> 3

## Dedup finds zero duplicates (no raw counterpart for orphans)
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-zset-orphan', @zset_key, stats, false, false)
stats[:duplicates_removed]
#=> 0

# -------------------------------------------------------------------
# Regular set deduplication (srem only)
# -------------------------------------------------------------------

## Setup set with raw + quoted duplicates
@redis.del(@set_key)
@redis.sadd(@set_key, 'member1')
@redis.sadd(@set_key, '"member1"')
@redis.sadd(@set_key, 'member2')
@redis.sadd(@set_key, '"member2"')
@redis.sadd(@set_key, 'member3')
@redis.scard(@set_key)
#=> 5

## Dry-run set dedup: no changes made
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-set', @set_key, stats, true, false)
[@redis.scard(@set_key), stats[:duplicates_removed]]
#=> [5, 2]

## Run-mode set dedup: quoted duplicates removed
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-set', @set_key, stats, false, false)
[@redis.scard(@set_key), stats[:duplicates_removed]]
#=> [3, 2]

## After dedup, only raw members remain in set
remaining = @redis.smembers(@set_key).sort
remaining
#=> ["member1", "member2", "member3"]

# -------------------------------------------------------------------
# Set with only quoted members (no raw counterpart)
# -------------------------------------------------------------------

## Setup set with orphan quoted members only
@redis.del(@set_key)
@redis.sadd(@set_key, '"orphan_a"')
@redis.sadd(@set_key, '"orphan_b"')
@redis.sadd(@set_key, 'raw_c')
@redis.scard(@set_key)
#=> 3

## Dedup finds zero duplicates in set (no raw counterpart)
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-set-orphan', @set_key, stats, false, false)
stats[:duplicates_removed]
#=> 0

# -------------------------------------------------------------------
# Empty collection handling
# -------------------------------------------------------------------

## Empty sorted set: scans but finds nothing
@redis.del(@zset_key)
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-empty-zset', @zset_key, stats, false, false)
[stats[:keys_scanned], stats[:keys_with_duplicates], stats[:duplicates_removed]]
#=> [1, 0, 0]

## Empty set: scans but finds nothing
@redis.del(@set_key)
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-empty-set', @set_key, stats, false, false)
[stats[:keys_scanned], stats[:keys_with_duplicates], stats[:duplicates_removed]]
#=> [1, 0, 0]

# -------------------------------------------------------------------
# No duplicates present
# -------------------------------------------------------------------

## Sorted set with no duplicates: clean pass
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'clean1')
@redis.zadd(@zset_key, 2.0, 'clean2')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-clean-zset', @zset_key, stats, false, false)
[stats[:keys_scanned], stats[:keys_with_duplicates], stats[:duplicates_removed]]
#=> [1, 0, 0]

## Set with no duplicates: clean pass
@redis.del(@set_key)
@redis.sadd(@set_key, 'clean1')
@redis.sadd(@set_key, 'clean2')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-clean-set', @set_key, stats, false, false)
[stats[:keys_scanned], stats[:keys_with_duplicates], stats[:duplicates_removed]]
#=> [1, 0, 0]

# -------------------------------------------------------------------
# Stats tracking accuracy across multiple calls
# -------------------------------------------------------------------

## Stats accumulate correctly across multiple sorted set scans
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'x')
@redis.zadd(@zset_key, 2.0, '"x"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
# Dry run first pass
@cmd.send(:dedupe_sorted_set, 'pass1', @zset_key, stats, true, false)
# Re-populate for second pass (since dry run doesn't remove)
@redis.zadd(@zset_key, 3.0, 'y')
@redis.zadd(@zset_key, 4.0, '"y"')
@cmd.send(:dedupe_sorted_set, 'pass2', @zset_key, stats, true, false)
[stats[:keys_scanned], stats[:keys_with_duplicates], stats[:duplicates_removed]]
#=> [2, 2, 3]

# -------------------------------------------------------------------
# Verbose mode produces output without errors
# -------------------------------------------------------------------

## Verbose mode with sorted set duplicates runs without error
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'verb')
@redis.zadd(@zset_key, 2.0, '"verb"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-verbose', @zset_key, stats, true, true)
stats[:duplicates_removed]
#=> 1

## Verbose mode with set duplicates runs without error
@redis.del(@set_key)
@redis.sadd(@set_key, 'verb')
@redis.sadd(@set_key, '"verb"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-verbose-set', @set_key, stats, true, true)
stats[:duplicates_removed]
#=> 1

# -------------------------------------------------------------------
# Error handling: bad key type triggers error capture
# -------------------------------------------------------------------

## Error on wrong key type is captured in stats
@redis.del(@zset_key)
@redis.set(@zset_key, 'not-a-sorted-set')
@err_stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'test-wrong-type', @zset_key, @err_stats, false, false)
@err_stats[:errors].size
#=> 1

## Error message contains the label
@err_stats[:errors].first.include?('test-wrong-type')
#=> true

## Error on wrong key type for set is captured
@redis.del(@set_key)
@redis.set(@set_key, 'not-a-set')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_set, 'test-wrong-type-set', @set_key, stats, false, false)
stats[:errors].size
#=> 1

# -------------------------------------------------------------------
# Idempotency: running dedup twice produces same result
# -------------------------------------------------------------------

## Running dedup twice is idempotent
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'idem')
@redis.zadd(@zset_key, 2.0, '"idem"')
stats1 = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'idem1', @zset_key, stats1, false, false)
stats2 = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'idem2', @zset_key, stats2, false, false)
[stats1[:duplicates_removed], stats2[:duplicates_removed], @redis.zcard(@zset_key)]
#=> [1, 0, 1]

# -------------------------------------------------------------------
# Score preservation: verify the raw member's score is unchanged
# -------------------------------------------------------------------

## After dedup, raw member retains its original score
@redis.del(@zset_key)
@redis.zadd(@zset_key, 42.5, 'scored')
@redis.zadd(@zset_key, 99.0, '"scored"')
@cmd.send(:dedupe_sorted_set, 'score-test', @zset_key, { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, errors: [] }, false, false)
@redis.zscore(@zset_key, 'scored')
#=> 42.5

# -------------------------------------------------------------------
# Sorted set normalization (zrem + zadd with preserved score)
# -------------------------------------------------------------------

## Normalize sorted set: orphan quoted members replaced with unquoted
@redis.del(@zset_key)
@redis.zadd(@zset_key, 10.0, '"orphan_a"')
@redis.zadd(@zset_key, 20.0, '"orphan_b"')
@redis.zadd(@zset_key, 30.0, 'already_raw')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'norm-zset', @zset_key, stats, false, false)
[stats[:members_normalized], @redis.zcard(@zset_key)]
#=> [2, 3]

## After normalization, quoted members are replaced by raw forms
remaining = @redis.zrange(@zset_key, 0, -1).sort
remaining
#=> ["already_raw", "orphan_a", "orphan_b"]

## Normalization preserves the original score
@redis.zscore(@zset_key, 'orphan_a')
#=> 10.0

## Normalization preserves the second member's score too
@redis.zscore(@zset_key, 'orphan_b')
#=> 20.0

## Dry-run normalization: no changes made
@redis.del(@zset_key)
@redis.zadd(@zset_key, 5.0, '"dry_orphan"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'norm-dry', @zset_key, stats, true, false)
[stats[:members_normalized], @redis.zrange(@zset_key, 0, -1)]
#=> [1, ["\"dry_orphan\""]]

## Normalize skips members that already have raw counterpart (handled by dedup)
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'both')
@redis.zadd(@zset_key, 2.0, '"both"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'norm-skip', @zset_key, stats, false, false)
stats[:members_normalized]
#=> 0

## Normalize on empty sorted set: no-op
@redis.del(@zset_key)
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'norm-empty', @zset_key, stats, false, false)
stats[:members_normalized]
#=> 0

# -------------------------------------------------------------------
# Regular set normalization (srem + sadd)
# -------------------------------------------------------------------

## Normalize set: orphan quoted members replaced with unquoted
@redis.del(@set_key)
@redis.sadd(@set_key, '"set_orphan_x"')
@redis.sadd(@set_key, '"set_orphan_y"')
@redis.sadd(@set_key, 'set_raw')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_set, 'norm-set', @set_key, stats, false, false)
[stats[:members_normalized], @redis.scard(@set_key)]
#=> [2, 3]

## After set normalization, quoted members are replaced by raw forms
remaining = @redis.smembers(@set_key).sort
remaining
#=> ["set_orphan_x", "set_orphan_y", "set_raw"]

## Dry-run set normalization: no changes made
@redis.del(@set_key)
@redis.sadd(@set_key, '"dry_set_orphan"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_set, 'norm-set-dry', @set_key, stats, true, false)
[stats[:members_normalized], @redis.smembers(@set_key)]
#=> [1, ["\"dry_set_orphan\""]]

## Normalize set skips members that already have raw counterpart
@redis.del(@set_key)
@redis.sadd(@set_key, 'exists')
@redis.sadd(@set_key, '"exists"')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_set, 'norm-set-skip', @set_key, stats, false, false)
stats[:members_normalized]
#=> 0

## Normalize set on empty set: no-op
@redis.del(@set_key)
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_set, 'norm-set-empty', @set_key, stats, false, false)
stats[:members_normalized]
#=> 0

# -------------------------------------------------------------------
# Normalization error handling
# -------------------------------------------------------------------

## Normalize sorted set error is captured in stats
@redis.del(@zset_key)
@redis.set(@zset_key, 'not-a-sorted-set')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'norm-err', @zset_key, stats, false, false)
stats[:errors].size
#=> 1

## Normalize set error is captured in stats
@redis.del(@set_key)
@redis.set(@set_key, 'not-a-set')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_set, 'norm-set-err', @set_key, stats, false, false)
stats[:errors].size
#=> 1

# -------------------------------------------------------------------
# Full dedup + normalize pipeline on sorted set
# -------------------------------------------------------------------

## Full pipeline: dedup removes duplicates, normalize fixes orphans
@redis.del(@zset_key)
@redis.zadd(@zset_key, 1.0, 'has_both')
@redis.zadd(@zset_key, 2.0, '"has_both"')
@redis.zadd(@zset_key, 3.0, '"orphan_only"')
@redis.zadd(@zset_key, 4.0, 'clean')
stats = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:dedupe_sorted_set, 'pipeline', @zset_key, stats, false, false)
@cmd.send(:normalize_sorted_set, 'pipeline', @zset_key, stats, false, false)
remaining = @redis.zrange(@zset_key, 0, -1).sort
[stats[:duplicates_removed], stats[:members_normalized], remaining]
#=> [1, 1, ["clean", "has_both", "orphan_only"]]

## Pipeline preserves orphan's score after normalization
@redis.zscore(@zset_key, 'orphan_only')
#=> 3.0

# -------------------------------------------------------------------
# Normalization idempotency
# -------------------------------------------------------------------

## Running normalize twice is idempotent
@redis.del(@zset_key)
@redis.zadd(@zset_key, 7.0, '"once"')
stats1 = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'idem-norm1', @zset_key, stats1, false, false)
stats2 = { keys_scanned: 0, keys_with_duplicates: 0, duplicates_removed: 0, members_normalized: 0, errors: [] }
@cmd.send(:normalize_sorted_set, 'idem-norm2', @zset_key, stats2, false, false)
[stats1[:members_normalized], stats2[:members_normalized], @redis.zrange(@zset_key, 0, -1)]
#=> [1, 0, ["once"]]

# Teardown: clean up test keys
@redis.del(@zset_key, @set_key)
