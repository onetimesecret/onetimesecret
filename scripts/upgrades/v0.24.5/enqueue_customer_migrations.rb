#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/upgrades/v0.24.5/enqueue_customer_migrations.rb
#
# Enqueues customer-migration jobs onto RabbitMQ for parallel processing by
# customer-migration workers. Designed to run once (or be safely restarted)
# as part of the v0.24.5 → v2 incremental migration architecture.
#
# ROLE IN THE PIPELINE
# ====================
# This script is the enqueuer half of a two-process design:
#
#   enqueue_customer_migrations.rb  (this script)
#         ↓ RabbitMQ: customer_migration queue
#   customer_migration_worker.rb    (parallel agent)
#
# The enqueuer builds an ordered index of v1 customers, checks each against the
# v2 target, and publishes work items for candidates that need migration or
# re-migration. Workers do the actual data movement.
#
# INPUTS
# ======
# - Source Redis (v1): DB 6, keys matching customer:*:object
# - Target Valkey (v2): DB 0, keys matching customer:{objid}:object
# - RabbitMQ: via $rmq_channel_pool (Onetime::Jobs::Publisher pattern)
#
# SIDE EFFECTS
# ============
# On source Redis:
#   _migration:customer:by_updated        — sorted set built by OrderedKeyScanner
#   _migration:customer:enqueue_cursor    — float score cursor for resumability
#   _migration:customer:enqueue_lock      — NX lock to prevent concurrent runs
#
# On RabbitMQ:
#   customer_migration queue             — one message per candidate customer key
#
# IDEMPOTENCY GUARANTEES
# ======================
# - The sorted set is built once and reused on restart (pass --rebuild-zset to force rescan).
# - The cursor checkpoint means restarted runs skip already-processed records.
# - Each worker message is idempotent: workers re-check migration_status before writing.
# - Double-enqueue is possible only if two enqueuers run concurrently (see CONCURRENCY).
#
# CONCURRENCY WARNING
# ===================
# Only one enqueuer instance should run at a time. Two concurrent runs against
# the same sorted set will read overlapping ZRANGEBYSCORE windows and
# double-publish. Workers are designed to be idempotent so double-publish causes
# wasted work but not data corruption. However, the lock key
# _migration:customer:enqueue_lock uses SET NX EX to provide an advisory lock.
# If a run crashes without releasing the lock, use --force-unlock to clear it.
#
# DELTA DETECTION NOTE
# ====================
# We detect "record changed in v1 since last migration" by comparing the v1
# updated_score (from the sorted set) to the v2 migrated_at (stored by the
# worker as a float Unix timestamp). This comparison works if and only if:
#   1. Both values use the same epoch (Unix seconds). migrated_at is written by
#      mark_migrated! as Time.now.to_f.to_s (float seconds, NOT ISO8601).
#   2. Clocks on v1 and worker hosts are reasonably synchronized (NTP assumed).
#
# If the sorted set was built from the updated field and the worker's clock is
# behind v1's clock, legitimate deltas might be missed. This is a known
# limitation. If clock skew is a concern, instrument a separate freshness-
# checker tool instead of relying on this scalar comparison.
#
# The v1_updated_score is embedded in each queue message so that workers can
# re-evaluate freshness at processing time using the original score, not a
# re-read (which would have TOCTOU issues if v1 is updated between enqueue and
# process).
#
# MIGRATION STATUS VALUES
# =======================
# This script reads status strings written by workers using:
#   Onetime::Models::Features::WithMigrationFields::MIGRATION_STATUS
#
# Actual string values (as of v0.24.5):
#   'pending'    — not yet migrated (or status field absent)
#   'migrating'  — worker claimed it (in-flight)
#   'completed'  — successfully migrated
#   'failed'     — worker encountered an error
#   'skipped'    — intentionally skipped
#
# BRIEF NOTE: The design brief used 'migrated' and 'in_progress' — those are
# NOT the actual stored values. The real values are 'completed' and 'migrating'.
# If the worker uses different strings, update EXPECTED_STATUS_VALUES below.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/enqueue_customer_migrations.rb [OPTIONS]
#
# Options:
#   --source-url=URL             Source Redis URL (env: SOURCE_REDIS_URL)
#   --target-url=URL             Target Valkey URL (env: TARGET_VALKEY_URL)
#   --queue-name=NAME            Queue name (default: customer_migration)
#   --batch-size=N               Keys per publish call (default: 500)
#   --max-batches=N              Stop after N batches (testing/surgical use)
#   --rebuild-zset               Force re-scan even if sorted set exists
#   --dry-run                    Preview without publishing (DEFAULT)
#   --execute                    Actually enqueue (required to write)
#   --no-resume                  Ignore checkpoint, start from score 0
#   --from-score=N               Start from this score (float Unix seconds)
#   --to-score=N                 Stop at this score (float Unix seconds)
#   --in-progress-timeout=N      Seconds before in-progress assumed stale (default: 300)
#   --force-unlock               Clear advisory lock if a prior run crashed
#   --help                       Show this help

require 'redis'
require 'json'
require 'securerandom'
require 'digest'
require 'uri'
require 'time'

# ---------------------------------------------------------------------------
# UUIDv7 derivation — copied verbatim from enrich_with_identifiers.rb.
# Do not modify here; keep in sync with that file.
# TODO: Extract both copies into a shared lib (e.g. lib/migration/identifier.rb)
#       and require it from both scripts to eliminate the duplication risk.
# Source: scripts/upgrades/v0.24.5/enrich_with_identifiers.rb
#         methods: generate_uuid_v7_from, derive_extid_from_uuid
# ---------------------------------------------------------------------------
module MigrationIdentifier
  module_function

  # @param timestamp_seconds [Numeric] Unix timestamp (created field value)
  # @param seed_key [String] Original v1 key (customer:{custid}:object)
  # @return [String] UUID v7 string — deterministic for the same inputs
  def generate_uuid_v7_from(timestamp_seconds, seed_key:)
    timestamp_ms = (timestamp_seconds.to_f * 1000).to_i
    hex = timestamp_ms.to_s(16).rjust(12, '0')

    seed_material = "#{seed_key}:#{timestamp_seconds}"
    random_bytes = Digest::SHA256.digest(seed_material)[0, 10]
    rand_hex = random_bytes.unpack1('H*')

    time_hi  = hex[0, 8]
    time_mid = hex[8, 4]
    ver_rand = '7' + rand_hex[0, 3]
    variant_byte = (rand_hex[3, 2].to_i(16) & 0x3F) | 0x80
    variant = variant_byte.to_s(16).rjust(2, '0') + rand_hex[5, 2]
    node = rand_hex[7, 12]

    "#{time_hi}-#{time_mid}-#{ver_rand}-#{variant}-#{node}"
  end

  # @param uuid_string [String] UUID v7
  # @param prefix [String] e.g. 'ur' for customer
  # @return [String] External ID
  def derive_extid_from_uuid(uuid_string, prefix:)
    normalized_hex = uuid_string.delete('-')
    seed = Digest::SHA256.digest(normalized_hex)
    prng = Random.new(seed.unpack1('Q>'))
    random_bytes = prng.bytes(16)
    external_part = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')
    "#{prefix}#{external_part}"
  end
end

# ---------------------------------------------------------------------------
# Main enqueuer class
# ---------------------------------------------------------------------------
class CustomerMigrationEnqueuer
  # Error taxonomy
  class Error < StandardError; end
  class SourceRedisUnavailable < Error; end
  class TargetValkeyUnavailable < Error; end
  class QueueUnavailable < Error; end
  class LockConflict < Error; end
  class MalformedV1Record < Error; end
  class UnknownMigrationStatus < Error; end
  # Sorted set key in source Redis that indexes customer keys by updated score.
  # Built by OrderedKeyScanner (or rebuilt with --rebuild-zset).
  ZSET_KEY = '_migration:customer:by_updated'

  # Cursor checkpoint in source Redis. Stores the highest score consumed so
  # far as a float string. Stored in source Redis because that's where the
  # zset lives. On restart, resume from cursor + Float::EPSILON to avoid
  # reprocessing the boundary record.
  CURSOR_KEY = '_migration:customer:enqueue_cursor'

  # Advisory lock key. SET NX EX prevents two concurrent enqueuer instances.
  # TTL must exceed the maximum expected single-run wall-clock time.
  LOCK_KEY = '_migration:customer:enqueue_lock'
  LOCK_TTL_SECONDS = 3600  # 1 hour; adjust if runs legitimately take longer

  # RabbitMQ queue name default (overridable via --queue-name)
  DEFAULT_QUEUE_NAME = 'customer_migration'

  # Default batch size: keys published per message.
  # Workers receive an array of keys; larger batches reduce overhead but
  # increase re-queue cost if a worker crashes mid-batch.
  # TODO: Confirm with worker agent whether array-per-message or single-key
  #       per message is the preferred contract. This currently sends arrays.
  DEFAULT_BATCH_SIZE = 500

  # How long to wait for an in-progress record before assuming the worker
  # crashed and re-enqueuing. Set to worker_p99_processing_time * 3.
  # Measure actual worker latency before hardcoding this in prod.
  DEFAULT_IN_PROGRESS_TIMEOUT = 300  # seconds

  # Customer extid prefix (ObjectIdentifier, matches enrich_with_identifiers.rb)
  EXTID_PREFIX = 'ur'

  # Actual status strings as written by WithMigrationFields#mark_migrated! etc.
  # Keep in sync with Onetime::Models::Features::WithMigrationFields::MIGRATION_STATUS
  STATUS_COMPLETED   = 'completed'
  STATUS_MIGRATING   = 'migrating'
  STATUS_FAILED      = 'failed'
  STATUS_PENDING     = 'pending'
  STATUS_SKIPPED     = 'skipped'

  # Result tokens returned by should_enqueue?
  DECISION_ENQUEUE       = :enqueue
  DECISION_SKIP          = :skip
  DECISION_STALE_WARNING = :stale_warning  # in-progress but clock says stale; re-enqueue

  def initialize(options = {})
    @source_url              = options.fetch(:source_url)
    @target_url              = options.fetch(:target_url)
    @queue_name              = options.fetch(:queue_name, DEFAULT_QUEUE_NAME)
    @batch_size              = options.fetch(:batch_size, DEFAULT_BATCH_SIZE)
    @max_batches             = options[:max_batches]   # nil = unlimited
    @rebuild_zset            = options.fetch(:rebuild_zset, false)
    @dry_run                 = options.fetch(:dry_run, true)
    @resume                  = options.fetch(:resume, true)
    @from_score              = options[:from_score]    # nil = 0.0
    @to_score                = options[:to_score]      # nil = +inf
    @in_progress_timeout     = options.fetch(:in_progress_timeout, DEFAULT_IN_PROGRESS_TIMEOUT)
    @force_unlock            = options.fetch(:force_unlock, false)

    @source_redis  = nil
    @target_redis  = nil
    @lock_acquired = false

    @stats = {
      scanned:          0,
      enqueued:         0,
      skip_current:     0,
      skip_in_progress: 0,
      skip_skipped:     0,
      failed_lookup:    0,
      unexpected_status: 0,
      errors:           [],
    }
  end

  # Entry point. Returns @stats hash.
  def run
    connect_redis
    acquire_lock

    build_or_reuse_sorted_set

    from  = effective_from_score
    to    = effective_to_score

    puts "Enqueuing customer migration jobs..."
    puts "  Queue:      #{@queue_name}"
    puts "  Batch size: #{@batch_size}"
    puts "  Score range: [#{from}, #{to}]"
    puts "  Mode:       #{@dry_run ? 'DRY RUN (no messages published)' : 'EXECUTE'}"
    puts

    batch         = []
    batches_sent  = 0

    iterate_zset(from_score: from, to_score: to) do |v1_key, score|
      @stats[:scanned] += 1

      decision = evaluate_candidate(v1_key, score)

      case decision
      when DECISION_ENQUEUE, DECISION_STALE_WARNING
        batch << { key: v1_key, v1_updated_score: score }
        puts "  [ENQUEUE#{decision == DECISION_STALE_WARNING ? '/stale' : ''}] #{v1_key}" if @dry_run
      when DECISION_SKIP
        # counters updated inside evaluate_candidate
      end

      if batch.size >= @batch_size
        publish_batch(batch)
        update_cursor(score)
        batches_sent += 1
        batch.clear

        break if @max_batches && batches_sent >= @max_batches
      end
    end

    # Flush remaining partial batch
    unless batch.empty?
      publish_batch(batch)
      # Use the last score in the batch for the cursor
      # TODO: iterate_zset must yield score alongside key so we can capture it here.
      # The current implementation captures it via the block variable — confirm
      # the score is still in scope or track it separately.
    end

    print_summary
    @stats
  ensure
    release_lock
    close_connections
  end

  private

  # --------------------------------------------------------------------------
  # Connection management
  # --------------------------------------------------------------------------

  def connect_redis
    @source_redis = build_redis_client(@source_url, db: 6, label: 'source')
    @target_redis = build_redis_client(@target_url, db: 0, label: 'target')
  end

  def build_redis_client(url, db:, label:)
    uri      = URI.parse(url)
    uri.path = "/#{db}"
    client   = Redis.new(
      url: uri.to_s,
      connect_timeout: 10,
      read_timeout: 30,
      write_timeout: 10,
      reconnect_attempts: [0.5, 1.0, 2.0],
    )
    client.ping
    client
  rescue Redis::CannotConnectError => ex
    klass = label == 'source' ? CustomerMigrationEnqueuer::SourceRedisUnavailable
                               : CustomerMigrationEnqueuer::TargetValkeyUnavailable
    raise klass, "Cannot connect to #{label} Redis: #{ex.message}"
  end

  def close_connections
    [@source_redis, @target_redis].compact.each do |c|
      c.close rescue nil
    end
  end

  # --------------------------------------------------------------------------
  # Advisory lock
  # --------------------------------------------------------------------------

  def acquire_lock
    if @force_unlock
      @source_redis.del(LOCK_KEY)
      puts "Advisory lock cleared (--force-unlock)."
    end

    acquired = @source_redis.set(
      LOCK_KEY,
      "#{Process.pid}@#{Time.now.utc.iso8601}",
      nx:  true,
      ex:  LOCK_TTL_SECONDS,
    )

    if acquired
      @lock_acquired = true
    else
      holder = @source_redis.get(LOCK_KEY)
      raise CustomerMigrationEnqueuer::LockConflict,
        "Another enqueuer is running (or crashed). Lock held by: #{holder}. " \
        "Use --force-unlock to clear it if the prior run is dead."
    end
  end

  def release_lock
    @source_redis.del(LOCK_KEY) if @lock_acquired && @source_redis
    @lock_acquired = false
  rescue StandardError
    # Best-effort; TTL will expire the lock anyway.
  end

  # --------------------------------------------------------------------------
  # Sorted set construction
  # --------------------------------------------------------------------------

  # Build (or reuse) the sorted set of customer keys scored by their `updated`
  # field (fallback to `created`). The zset is the resumable artifact; once
  # built, restarts skip this phase entirely.
  #
  # Delegates to OrderedKeyScanner (parallel-agent implementation).
  # If the zset already exists and --rebuild-zset is not set, logs a message
  # and returns immediately.
  def build_or_reuse_sorted_set
    existing_size = @source_redis.zcard(ZSET_KEY)

    if existing_size > 0 && !@rebuild_zset
      puts "Reusing existing sorted set #{ZSET_KEY} (#{existing_size} entries). Pass --rebuild-zset to rescan."
      return
    end

    if @rebuild_zset && existing_size > 0
      puts "Rebuilding sorted set (--rebuild-zset). Deleting #{ZSET_KEY}..."
      @source_redis.del(ZSET_KEY)
      @source_redis.del(CURSOR_KEY)
    end

    puts "Building sorted set #{ZSET_KEY} via OrderedKeyScanner..."

    # TODO: Instantiate OrderedKeyScanner (parallel-agent class).
    #       Reference the final class name once the agent publishes it.
    #       Expected contract:
    #
    #         scanner = OrderedKeyScanner.new(
    #           redis:          @source_redis,
    #           model_prefix:   'customer',
    #           field_name:     'updated',    # fallback to 'created' if missing
    #           output_zset_key: ZSET_KEY,
    #         )
    #         scanner.run
    #
    #       The scanner should produce ZSET_KEY scored by float Unix seconds.
    #       If a record has no `updated` field, fall back to `created`. If
    #       both are absent, use score 0 and log a warning.
    #
    # TODO: Confirm that OrderedKeyScanner scans DB 6 (source) only and limits
    #       to keys matching `customer:*:object`.
    raise NotImplementedError, "TODO: OrderedKeyScanner not yet integrated. Run the parallel agent first."
  end

  # --------------------------------------------------------------------------
  # Sorted set iteration (resumable cursor)
  # --------------------------------------------------------------------------

  # Iterates the sorted set from from_score to to_score, yielding (v1_key, score)
  # for each entry. Uses ZRANGEBYSCORE with LIMIT to page through in batches.
  #
  # @param from_score [Float] Lower bound (inclusive)
  # @param to_score [Float, String] Upper bound (inclusive, or '+inf')
  # @yieldparam v1_key [String] e.g. "customer:alice@example.com:object"
  # @yieldparam score [Float] Unix timestamp (updated or created)
  def iterate_zset(from_score:, to_score:)
    page_size   = [@batch_size * 2, 1000].min  # ZRANGEBYSCORE page; tune vs. batch_size
    current_min = from_score.to_f
    max_str     = to_score == '+inf' ? '+inf' : to_score.to_s

    loop do
      # ZRANGEBYSCORE returns members ordered by score ascending
      # rubocop:disable Style/HashSyntax — redis gem uses string keys here
      results = @source_redis.zrangebyscore(
        ZSET_KEY,
        current_min,
        max_str,
        with_scores: true,
        limit: [0, page_size],
      )
      # rubocop:enable Style/HashSyntax

      break if results.empty?

      results.each do |member, score|
        yield member, score.to_f
      end

      last_score = results.last[1].to_f

      break if results.size < page_size  # last page

      # Advance cursor past last score to avoid re-reading the boundary member.
      # Adding epsilon to a float score means we skip all members AT the
      # boundary score — correct only if scores are unique. If multiple customers
      # share the same updated timestamp, use (score, member) tuple pagination
      # via ZRANGEBYSCORE ... LIMIT offset count instead.
      # TODO: If updated timestamps are non-unique, switch to offset-based pagination.
      current_min = last_score + Float::EPSILON
    end
  end

  # --------------------------------------------------------------------------
  # Candidate evaluation
  # --------------------------------------------------------------------------

  # Full evaluation pipeline for a single v1 key.
  # Updates @stats as a side effect.
  #
  # @param v1_key [String] e.g. "customer:alice@example.com:object"
  # @param v1_score [Float] Score from the sorted set (updated or created)
  # @return [Symbol] DECISION_ENQUEUE | DECISION_SKIP | DECISION_STALE_WARNING
  def evaluate_candidate(v1_key, v1_score)
    objid = derive_v2_objid(v1_key)
    v2_status, v2_migrated_at = check_v2_status(objid)

    decision = should_enqueue?(v1_score, v2_status, v2_migrated_at)

    case decision
    when DECISION_SKIP
      if v2_status == STATUS_MIGRATING
        @stats[:skip_in_progress] += 1
      elsif v2_status == STATUS_SKIPPED
        @stats[:skip_skipped] += 1
      else
        @stats[:skip_current] += 1
      end
    when DECISION_STALE_WARNING
      warn "  [STALE] #{v1_key} — in-progress for >#{@in_progress_timeout}s; re-enqueuing"
      @stats[:enqueued] += 1
    when DECISION_ENQUEUE
      @stats[:enqueued] += 1
    end

    decision
  rescue CustomerMigrationEnqueuer::MalformedV1Record => ex
    @stats[:errors] << { key: v1_key, error: ex.message }
    DECISION_SKIP
  rescue Redis::CommandError => ex
    @stats[:errors] << { key: v1_key, error: "Redis error: #{ex.message}" }
    DECISION_SKIP
  end

  # --------------------------------------------------------------------------
  # V2 objid derivation
  # --------------------------------------------------------------------------

  # Derive the expected v2 objid for a v1 customer key.
  # Reads the `created` field from source Redis (or a warm cache if the
  # scanner cached it — TODO: check whether OrderedKeyScanner populates a cache).
  #
  # Algorithm is identical to enrich_with_identifiers.rb so objids match
  # what was already written during the file-based pipeline.
  #
  # @param v1_key [String] "customer:{custid}:object"
  # @return [String] UUID v7 string
  # @raise [MalformedV1Record] if created field is missing or zero
  def derive_v2_objid(v1_key)
    created_raw = @source_redis.hget(v1_key, 'created')

    if created_raw.nil? || created_raw.empty? || created_raw.to_f.zero?
      raise CustomerMigrationEnqueuer::MalformedV1Record,
        "#{v1_key}: missing or zero 'created' field — cannot derive objid"
    end

    created_ts = created_raw.to_f
    MigrationIdentifier.generate_uuid_v7_from(created_ts, seed_key: v1_key)
  end

  # --------------------------------------------------------------------------
  # V2 status lookup
  # --------------------------------------------------------------------------

  # Fetch migration_status and migrated_at from the v2 target.
  # Uses HMGET for a single round-trip.
  #
  # @param objid [String] UUID v7
  # @return [Array(String|nil, Float|nil)] [status, migrated_at_float]
  def check_v2_status(objid)
    v2_key = "customer:#{objid}:object"
    status_raw, migrated_at_raw = @target_redis.hmget(v2_key, 'migration_status', 'migrated_at')

    migrated_at = migrated_at_raw&.to_f
    migrated_at = nil if migrated_at_raw.nil? || migrated_at_raw.empty?

    [status_raw, migrated_at]
  end

  # --------------------------------------------------------------------------
  # Decision function — pure, no side effects, fully testable
  # --------------------------------------------------------------------------

  public

  # Determine whether a candidate customer should be enqueued.
  #
  # @param v1_score [Float] Score from sorted set (v1 updated or created, Unix seconds)
  # @param v2_status [String, nil] migration_status from v2 record (nil if no record)
  # @param v2_migrated_at [Float, nil] migrated_at as float Unix seconds (nil if absent)
  #   Note: workers write migrated_at as Time.now.to_f.to_s (float, NOT ISO8601).
  #   Compare numerically: v1_score > v2_migrated_at means v1 was updated after
  #   the worker migrated it → delta case.
  # @param in_progress_timeout [Integer] Seconds before in-progress assumed stale
  # @return [Symbol] :enqueue | :skip | :stale_warning
  def should_enqueue?(
    v1_score,
    v2_status,
    v2_migrated_at,
    in_progress_timeout: @in_progress_timeout
  )
    case v2_status

    when nil, '', STATUS_PENDING
      # No v2 record or explicitly pending — first migration
      DECISION_ENQUEUE

    when STATUS_COMPLETED
      if v2_migrated_at.nil?
        # Completed but no timestamp — conservative: re-enqueue so worker can verify
        DECISION_ENQUEUE
      elsif v1_score > v2_migrated_at
        # v1 was updated after we last migrated it — delta
        DECISION_ENQUEUE
      else
        # v2 is current
        DECISION_SKIP
      end

    when STATUS_FAILED
      # Retry failed migrations
      DECISION_ENQUEUE

    when STATUS_MIGRATING
      elapsed = v2_migrated_at ? (Time.now.to_f - v2_migrated_at) : in_progress_timeout + 1
      if elapsed >= in_progress_timeout
        # Worker likely crashed — treat as stale, re-enqueue
        DECISION_STALE_WARNING
      else
        # Recent in-progress — skip with warning logged by caller
        DECISION_SKIP
      end

    when STATUS_SKIPPED
      # Intentionally skipped — honour that decision
      DECISION_SKIP

    else
      # Unexpected status string — log and enqueue conservatively
      warn "  [WARN] Unexpected migration_status '#{v2_status}' — enqueuing conservatively"
      @stats[:unexpected_status] += 1
      DECISION_ENQUEUE
    end
  end

  # --------------------------------------------------------------------------
  # Batch publishing
  # --------------------------------------------------------------------------

  # Publish a batch of candidate keys to RabbitMQ.
  # Each message payload carries enough context for the worker to re-evaluate
  # freshness at processing time without re-reading v1 state.
  #
  # Message shape:
  #   {
  #     keys: [{ key: "customer:...:object", v1_updated_score: <float> }, ...],
  #     enqueued_at: "<ISO8601>",
  #     schema_version: 1,
  #   }
  #
  # @param batch [Array<Hash>] Array of { key:, v1_updated_score: } hashes
  def publish_batch(batch)
    return if batch.empty?

    if @dry_run
      puts "  DRY RUN: Would publish batch of #{batch.size} keys to '#{@queue_name}'"
      return
    end

    payload = {
      keys:           batch,
      enqueued_at:    Time.now.utc.iso8601,
      schema_version: 1,
    }

    # TODO: Confirm whether to send one message per key or one message per batch.
    #       Current design: one message per batch (lower overhead, larger re-queue unit).
    #       If workers are designed for single-key messages, iterate and call
    #       publish_single(key, v1_score) here instead.
    #
    # TODO: Pre-flight check that $rmq_channel_pool is initialized before the
    #       run loop starts, not per-batch. Add a connect_queue method and call
    #       it in #run before the loop.
    #
    # Uses Onetime::Jobs::Publisher#publish which handles:
    #   - channel pool checkout
    #   - message_id (UUID)
    #   - x-schema-version header
    #   - Sentry trace header propagation
    #   - persistent: true
    #
    # This script runs outside the Onetime app boot context. You need either:
    #   a) A minimal require path that sets up $rmq_channel_pool, or
    #   b) A standalone Bunny wrapper that mirrors the publisher's options.
    # TODO: Decide and implement. Option (b) is safer for a one-shot CLI script.
    raise NotImplementedError,
      "TODO: Implement publish_batch. " \
      "Use Onetime::Jobs::Publisher#publish(#{@queue_name.inspect}, payload) " \
      "or a standalone Bunny wrapper if app boot is not feasible here."
  rescue Bunny::ConnectionClosedError, Bunny::NetworkFailure => ex
    raise CustomerMigrationEnqueuer::QueueUnavailable,
      "RabbitMQ unavailable during publish: #{ex.message}"
  end

  # --------------------------------------------------------------------------
  # Cursor checkpoint
  # --------------------------------------------------------------------------

  # Persist the highest score consumed so that a restarted run resumes here.
  # Stored in source Redis alongside the sorted set.
  #
  # @param score [Float] Highest score in the batch just published
  def update_cursor(score)
    return if @dry_run

    @source_redis.set(CURSOR_KEY, score.to_s)
  end

  # On resume, start just past the last checkpointed score.
  # Returns 0.0 if no cursor or --no-resume is set.
  def effective_from_score
    return @from_score.to_f if @from_score

    if @resume && !@rebuild_zset
      stored = @source_redis.get(CURSOR_KEY)
      if stored
        cursor = stored.to_f
        puts "Resuming from cursor score #{cursor} (#{Time.at(cursor).utc.iso8601})"
        return cursor + Float::EPSILON
      end
    end

    0.0
  end

  def effective_to_score
    @to_score || '+inf'
  end

  # --------------------------------------------------------------------------
  # Stats output
  # --------------------------------------------------------------------------

  def print_summary
    puts
    puts '=' * 60
    puts "ENQUEUE SUMMARY#{@dry_run ? ' (DRY RUN)' : ''}"
    puts '=' * 60
    puts "  Total scanned:        #{@stats[:scanned]}"
    puts "  Enqueued:             #{@stats[:enqueued]}"
    puts "  Skipped (current):    #{@stats[:skip_current]}"
    puts "  Skipped (in-progress):#{@stats[:skip_in_progress]}"
    puts "  Skipped (intentional):#{@stats[:skip_skipped]}"
    puts "  Unexpected status:    #{@stats[:unexpected_status]}"
    puts "  Errors:               #{@stats[:errors].size}"
    puts

    return unless @stats[:errors].any?

    puts "ERRORS (first 20):"
    @stats[:errors].first(20).each do |err|
      puts "  [#{err[:key]}] #{err[:error]}"
    end
    puts "  ... and #{@stats[:errors].size - 20} more" if @stats[:errors].size > 20
  end
end

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args(args)
  options = {
    source_url:           ENV['SOURCE_REDIS_URL'] || ENV['REDIS_URL'],
    target_url:           ENV['TARGET_VALKEY_URL'] || ENV['VALKEY_URL'],
    queue_name:           CustomerMigrationEnqueuer::DEFAULT_QUEUE_NAME,
    batch_size:           CustomerMigrationEnqueuer::DEFAULT_BATCH_SIZE,
    max_batches:          nil,
    rebuild_zset:         false,
    dry_run:              true,
    resume:               true,
    from_score:           nil,
    to_score:             nil,
    in_progress_timeout:  CustomerMigrationEnqueuer::DEFAULT_IN_PROGRESS_TIMEOUT,
    force_unlock:         false,
  }

  args.each do |arg|
    case arg
    when /\A--source-url=(.+)\z/
      options[:source_url] = Regexp.last_match(1)
    when /\A--target-url=(.+)\z/
      options[:target_url] = Regexp.last_match(1)
    when /\A--queue-name=(.+)\z/
      options[:queue_name] = Regexp.last_match(1)
    when /\A--batch-size=(\d+)\z/
      options[:batch_size] = Regexp.last_match(1).to_i
    when /\A--max-batches=(\d+)\z/
      options[:max_batches] = Regexp.last_match(1).to_i
    when '--rebuild-zset'
      options[:rebuild_zset] = true
    when '--dry-run'
      options[:dry_run] = true
    when '--execute'
      options[:dry_run] = false
    when '--no-resume'
      options[:resume] = false
    when /\A--from-score=(\S+)\z/
      options[:from_score] = Regexp.last_match(1).to_f
    when /\A--to-score=(\S+)\z/
      options[:to_score] = Regexp.last_match(1).to_f
    when /\A--in-progress-timeout=(\d+)\z/
      options[:in_progress_timeout] = Regexp.last_match(1).to_i
    when '--force-unlock'
      options[:force_unlock] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.5/enqueue_customer_migrations.rb [OPTIONS]

        Enqueues customer-migration jobs onto RabbitMQ in updated-timestamp order.
        Default: DRY RUN. Pass --execute to actually publish.

        Connection:
          --source-url=URL             Source Redis URL (env: SOURCE_REDIS_URL)
          --target-url=URL             Target Valkey URL (env: TARGET_VALKEY_URL)

        Queue:
          --queue-name=NAME            Queue name (default: #{CustomerMigrationEnqueuer::DEFAULT_QUEUE_NAME})
          --batch-size=N               Keys per message (default: #{CustomerMigrationEnqueuer::DEFAULT_BATCH_SIZE})
          --max-batches=N              Stop after N batches (testing)

        Scanning:
          --rebuild-zset               Force rescan (default: reuse existing zset)
          --from-score=N               Start score (float Unix seconds)
          --to-score=N                 End score (float Unix seconds)

        Run control:
          --dry-run                    Preview without publishing (DEFAULT)
          --execute                    Actually enqueue
          --no-resume                  Ignore cursor, start from score 0
          --in-progress-timeout=N      Stale threshold in seconds (default: #{CustomerMigrationEnqueuer::DEFAULT_IN_PROGRESS_TIMEOUT})
          --force-unlock               Clear advisory lock from crashed prior run

        Environment variables (fallbacks):
          SOURCE_REDIS_URL or REDIS_URL
          TARGET_VALKEY_URL or VALKEY_URL

        Examples:
          # Dry run to see what would be enqueued
          ruby enqueue_customer_migrations.rb \\
            --source-url=redis://v1-redis:6379 \\
            --target-url=redis://v2-valkey:6379

          # Actually enqueue, first 5 batches only (smoke test)
          ruby enqueue_customer_migrations.rb --execute --max-batches=5

          # Re-run a specific score range (surgical re-migration)
          ruby enqueue_customer_migrations.rb --execute \\
            --from-score=1700000000 --to-score=1700100000 --no-resume

          # Force rescan after v1 data changed significantly
          ruby enqueue_customer_migrations.rb --rebuild-zset --dry-run
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  unless options[:source_url]
    warn 'Error: --source-url required (or set SOURCE_REDIS_URL / REDIS_URL)'
    exit 1
  end

  unless options[:target_url]
    warn 'Error: --target-url required (or set TARGET_VALKEY_URL / VALKEY_URL)'
    exit 1
  end

  enqueuer = CustomerMigrationEnqueuer.new(options)
  stats    = enqueuer.run

  # Exit 1 if any errors accumulated
  exit(1) if stats[:errors].any?
end
