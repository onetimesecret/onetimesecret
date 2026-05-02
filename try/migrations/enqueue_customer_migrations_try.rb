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

require 'bunny-mock'

require_relative '../../scripts/upgrades/v0.24.5/enqueue_customer_migrations'

# Instantiate without Redis / RabbitMQ — we only exercise the pure decision method.
class TestableEnqueuer < CustomerMigrationEnqueuer
  def initialize
    @in_progress_timeout = DEFAULT_IN_PROGRESS_TIMEOUT
    @stats = Hash.new(0).merge(errors: [], unexpected_status: 0)
  end
end

# For publish_batch round-trip via bunny-mock — bypasses the constructor
# requiring source/target URLs.
class PublishingEnqueuer < CustomerMigrationEnqueuer
  attr_writer :rmq_channel

  def initialize(queue_name)
    @dry_run    = false
    @queue_name = queue_name
    @stats      = Hash.new(0).merge(errors: [])
  end
end

ENQUEUER = TestableEnqueuer.new

NOW      = Time.now.to_f
RECENT   = NOW - 60     # 1 minute ago — inside default 300s timeout
STALE    = NOW - 400    # 400 seconds ago — past default timeout
OLD      = NOW - 7200   # 2 hours ago — clearly before V1_SCORE
V1_SCORE = NOW - 3600   # v1 updated 1 hour ago (zset score)

# ---------------------------------------------------------------------------
# publish_batch fixture — exercises the real Bunny code path against bunny-mock.
# Setup runs once at load (before the first test); module-level constants
# persist across the per-test scopes that tryouts creates.
# ---------------------------------------------------------------------------
BunnyMock.use_bunny_queue_pop_api = true unless BunnyMock.use_bunny_queue_pop_api

PUB_QUEUE_NAME = 'migration.customer.batch'
PUB_CONN       = BunnyMock.new.start
PUB_CH         = PUB_CONN.create_channel
PUB_Q          = PUB_CH.queue(PUB_QUEUE_NAME, durable: true)
PUB_Q.bind(PUB_CH.default_exchange, routing_key: PUB_QUEUE_NAME)

PUB_ENQ             = PublishingEnqueuer.new(PUB_QUEUE_NAME)
PUB_ENQ.rmq_channel = PUB_CH
PUB_ENQ.send(:publish_batch, [
  { key: 'customer:alice@example.com:object', v1_updated_score: 1_700_000_001.5 },
  { key: 'customer:bob@example.com:object',   v1_updated_score: 1_700_000_002.0 },
])

PUB_RESULT = PUB_Q.pop
PUB_PROPS  = PUB_RESULT[1]
PUB_BODY   = JSON.parse(PUB_RESULT[2], symbolize_names: true)

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

# ---------------------------------------------------------------------------
# publish_batch — bunny-mock round-trip assertions
# ---------------------------------------------------------------------------
# Verifies the AMQP publish path produces a message matching the documented
# contract: persistent, application/json, message_id set, x-schema-version=1
# header, and a JSON body with :keys, :enqueued_at, :schema_version.
# Setup is at the top of this file (before the first test).

## publish_batch consumed exactly one message (queue drained after pop)
PUB_Q.message_count
#=> 0

## payload routes to the queue with persistent flag
PUB_PROPS[:persistent]
#=> true

## payload is JSON-typed
PUB_PROPS[:content_type]
#=> "application/json"

## message_id is a UUID string
PUB_PROPS[:message_id].is_a?(String) && PUB_PROPS[:message_id].length == 36
#=> true

## x-schema-version header is set to 1
PUB_PROPS[:headers]['x-schema-version']
#=> 1

## body :schema_version matches the contract
PUB_BODY[:schema_version]
#=> 1

## body :keys round-trips with key + v1_updated_score
PUB_BODY[:keys].size
#=> 2

## first key entry preserves the v1 key
PUB_BODY[:keys][0][:key]
#=> "customer:alice@example.com:object"

## first key entry preserves the v1_updated_score
PUB_BODY[:keys][0][:v1_updated_score]
#=> 1700000001.5

## :enqueued_at parses as ISO8601
!Time.iso8601(PUB_BODY[:enqueued_at]).nil?
#=> true
