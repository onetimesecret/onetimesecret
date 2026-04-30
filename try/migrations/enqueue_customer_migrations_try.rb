# try/migrations/enqueue_customer_migrations_try.rb
#
# frozen_string_literal: true

# Tests for CustomerMigrationEnqueuer#should_enqueue? — the pure decision
# function at the heart of the enqueuer. No Redis, no RabbitMQ.
#
# Run with:
#   try --agent try/migrations/enqueue_customer_migrations_try.rb
#
# The function under test:
#   should_enqueue?(v1_score, v2_status, v2_migrated_at, in_progress_timeout:)
#   → :enqueue | :skip | :stale_warning
#
# Status strings (from WithMigrationFields::MIGRATION_STATUS):
#   nil / '' / 'pending'   — no v2 record or pending
#   'completed'            — worker finished
#   'migrating'            — worker claimed it (in-flight)
#   'failed'               — worker errored
#   'skipped'              — intentionally skipped

require_relative '../../scripts/upgrades/v0.24.5/enqueue_customer_migrations'

# Instantiate without Redis / RabbitMQ — we only exercise the pure decision method.
class TestableEnqueuer < CustomerMigrationEnqueuer
  def initialize
    @in_progress_timeout = DEFAULT_IN_PROGRESS_TIMEOUT
    @stats = Hash.new(0).merge(errors: [], unexpected_status: 0)
  end
end

ENQUEUER = TestableEnqueuer.new

NOW      = Time.now.to_f
RECENT   = NOW - 60     # 1 minute ago — inside default 300s timeout
STALE    = NOW - 400    # 400 seconds ago — past default timeout
OLD      = NOW - 7200   # 2 hours ago — clearly before V1_SCORE
V1_SCORE = NOW - 3600   # v1 updated 1 hour ago (zset score)

## No v2 record (nil status) → first migration → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, nil, nil)
#=> :enqueue

## Empty string status → treat as no record → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, '', nil)
#=> :enqueue

## status='pending' → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, 'pending', nil)
#=> :enqueue

## status='completed', migrated_at AFTER v1 updated → already current → skip
ENQUEUER.should_enqueue?(V1_SCORE, 'completed', NOW)
#=> :skip

## status='completed', migrated_at BEFORE v1 updated → delta → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, 'completed', OLD)
#=> :enqueue

## status='completed', migrated_at nil → conservative → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, 'completed', nil)
#=> :enqueue

## status='failed' → retry → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, 'failed', nil)
#=> :enqueue

## status='migrating', migrated_at is RECENT (within 300s) → skip
ENQUEUER.should_enqueue?(V1_SCORE, 'migrating', RECENT, in_progress_timeout: 300)
#=> :skip

## status='migrating', migrated_at is STALE (past 300s) → assume crashed → stale_warning
ENQUEUER.should_enqueue?(V1_SCORE, 'migrating', STALE, in_progress_timeout: 300)
#=> :stale_warning

## status='migrating', migrated_at nil → elapsed treated as timeout+1 → stale_warning
ENQUEUER.should_enqueue?(V1_SCORE, 'migrating', nil, in_progress_timeout: 300)
#=> :stale_warning

## status='skipped' → honour it → skip
ENQUEUER.should_enqueue?(V1_SCORE, 'skipped', nil)
#=> :skip

## Unexpected status value → conservative → enqueue
ENQUEUER.should_enqueue?(V1_SCORE, 'garbage_value', nil)
#=> :enqueue

## Timeout boundary: elapsed == timeout → stale_warning (>= comparison)
ENQUEUER.should_enqueue?(V1_SCORE, 'migrating', NOW - 300, in_progress_timeout: 300)
#=> :stale_warning

## Timeout boundary: elapsed == timeout - 1 → still within tolerance → skip
ENQUEUER.should_enqueue?(V1_SCORE, 'migrating', NOW - 299, in_progress_timeout: 300)
#=> :skip

## Delta edge: v1_score exactly equal to migrated_at → not newer → skip
ENQUEUER.should_enqueue?(V1_SCORE, 'completed', V1_SCORE)
#=> :skip

## Delta edge: v1_score 1 second newer than migrated_at → enqueue
# Float::EPSILON is smaller than the ULP at Unix-timestamp scale (~1e9), so
# use a 1-second difference instead.
ENQUEUER.should_enqueue?(V1_SCORE, 'completed', V1_SCORE - 1.0)
#=> :enqueue
