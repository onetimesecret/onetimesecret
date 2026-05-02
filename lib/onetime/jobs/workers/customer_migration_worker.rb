# lib/onetime/jobs/workers/customer_migration_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'

module Onetime
  module Jobs
    module Workers
      # CustomerMigrationWorker — queue-driven v1→v2 customer migration
      #
      # Role:
      #   Consumes batches of v1 customer keys from RabbitMQ and migrates each
      #   customer record — including its generated Organization and
      #   OrganizationMembership — to target Valkey DB 0 in Familia v2 format.
      #
      # Boundaries:
      #   - ENQUEUER (separate agent): scans v1 Redis, emits batches of custids
      #     into `migration.customer.batch`. Does not write to target Valkey.
      #   - THIS WORKER: reads from queue, transforms, writes to target Valkey,
      #     archives v1 originals, marks status, acks.
      #   - ORCHESTRATOR (upgrade.sh / run_pipeline.sh): owns worker count,
      #     queue topology, and signals controlled shutdown.
      #
      # Concurrency:
      #   Two parallel instances of this worker class are expected (configured
      #   via MIGRATION_WORKER_THREADS env). The per-record idempotency fast-path
      #   (step 0 below) ensures safe re-delivery.
      #
      # Batch sizing rationale:
      #   500 custids × ~40 bytes/custid ≈ 20 KB message payload, well under
      #   the RabbitMQ default 128 KB frame limit. RESTORE operations are
      #   single-key, so no Redis transaction sizing constraint applies.
      #   If custid strings are longer (e.g., full email addresses), recalculate:
      #   batch_size = floor(100_000 / avg_custid_bytes).
      #
      # Pipeline flag:
      #   OTS_MIGRATION_PIPELINE (any truthy value) enables Redis pipelining
      #   for DUMP/RESTORE and HMSET fan-outs, matching the pattern in
      #   scripts/upgrades/v0.24.5/01-customer/transform.rb#pipeline_enabled?
      #
      # Per-customer processing order (see stubbed methods below):
      #   0. Idempotency fast-path
      #   1. read_v1_source_data
      #   2. derive_identifiers
      #   3. transform_to_v2
      #   4. generate_org_and_membership
      #   5. write_to_target_valkey
      #   6. update_indexes
      #   7. archive_v1_originals
      #   8. mark_migration_status
      #
      # Queue topology: 'migration.customer.batch' is registered in
      # QueueConfig::QUEUES with DLX dlx.migration.customer →
      # dlq.migration.customer (see lib/onetime/jobs/queues/config.rb).
      #
      # TODO (Phase 5 exclusion): Rodauth/auth account sync is explicitly out of
      # scope here. After migration completes, a separate command handles that.
      #
      class CustomerMigrationWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'migration.customer.batch'

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('MIGRATION_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('MIGRATION_WORKER_PREFETCH', 1).to_i

        # prefetch: 1 keeps the in-flight window tight during migration so a
        # worker crash only risks one batch. Raise to 2 if throughput is the
        # bottleneck and you are confident about the idempotency fast-path.

        # ── Error taxonomy ────────────────────────────────────────────────────

        # Raised when source Redis, target Valkey, or the queue itself is
        # unreachable. The entire batch is re-queued and the exception
        # propagates to the Sneakers supervisor.
        class HardInfrastructureError < StandardError; end

        # Raised for a single record when transform logic fails (bad data,
        # unexpected field, serializer error). The record is sent to the
        # per-record DLQ; the batch continues.
        class RecordTransformError < StandardError
          attr_reader :custid

          def initialize(msg, custid:)
            super(msg)
            @custid = custid
          end
        end

        # Raised when identifier derivation (objid/extid) produces an
        # inconsistent result (e.g., missing `created` timestamp). Treated
        # the same as RecordTransformError.
        class IdentifierDerivationError < RecordTransformError; end

        # Raised when target Valkey write fails for a single record in a way
        # that is clearly not an infrastructure failure (e.g., WRONGTYPE on a
        # single key). Treated as a per-record failure.
        class RecordWriteError < RecordTransformError; end

        # ── Entry point ───────────────────────────────────────────────────────

        # Process one batch message from the queue.
        #
        # @param msg [String] JSON-encoded batch payload from the enqueuer.
        #   Schema (see scripts/upgrades/v0.24.5/enqueue_customer_migrations.rb,
        #   CustomerMigrationEnqueuer#publish_batch):
        #     {
        #       "keys": [
        #         { "key": "customer:<custid>:object",
        #           "v1_updated_score": <float> },
        #         ...
        #       ],
        #       "enqueued_at": "<ISO8601>",
        #       "schema_version": 1
        #     }
        #   batch_id is taken from AMQP message_id (set by the enqueuer).
        # @param delivery_info [Bunny::DeliveryInfo]
        # @param metadata [Bunny::MessageProperties]
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          data = nil
          with_trace_context do
            data    = parse_message(msg)
            return unless data

            entries  = data[:keys]
            batch_id = message_id

            unless entries.is_a?(Array) && !entries.empty?
              log_error 'Batch payload missing or empty keys array', batch_id: batch_id
              return reject!
            end

            log_info 'Processing migration batch',
              batch_id: batch_id,
              size: entries.size,
              redelivered: delivery_info.redelivered?

            process_batch(entries, batch_id)

            log_info 'Migration batch complete', batch_id: batch_id, size: entries.size
            ack!
          end
        rescue HardInfrastructureError => ex
          log_error 'Hard infrastructure error — re-queuing batch', ex
          reject! # RabbitMQ will re-deliver; DLQ policy applies after x-dead-letter-count
        rescue StandardError => ex
          log_error 'Unexpected error processing batch', ex
          reject!
        end

        # ── Idempotency check ─────────────────────────────────────────────────

        # Self-class hook for boot-time validation.
        # TODO: verify source/target Redis URLs are present and reachable.
        def self.check_essentials!
          source_url = ENV.fetch('V1_REDIS_URL', nil)
          target_url = ENV.fetch('VALKEY_URL', ENV.fetch('REDIS_URL', nil))

          raise 'V1_REDIS_URL is required for CustomerMigrationWorker' unless source_url
          raise 'VALKEY_URL (or REDIS_URL) is required for CustomerMigrationWorker' unless target_url
        end

        private

        # ── Batch loop ────────────────────────────────────────────────────────

        def process_batch(entries, batch_id)
          # Sort oldest-first so queue stalls leave the most-recently-active
          # customers for later. The enqueuer publishes entries already
          # sorted oldest-first by the Lua+pipeline ordered scanner; the
          # v1_updated_score field is preserved here for re-sort/freshness
          # checks if the worker decides to use it.

          entries.each do |entry|
            # Each entry: { key: "customer:<custid>:object", v1_updated_score: <float> }
            # Stubbed downstream (see migrate_one) — implementation can pass
            # entry through or derive custid from entry[:key] as needed.
            migrate_one(entry, batch_id)
          rescue HardInfrastructureError
            raise # Propagate to work_with_params; abort entire batch
          rescue StandardError => ex
            # Per-record failure: classify, mark, ship to record DLQ, continue
            handle_per_record_failure(entry, ex, batch_id)
          end
        end

        # ── Per-record migration ───────────────────────────────────────────────

        def migrate_one(entry, _batch_id)
          # entry: { key: "customer:<custid>:object", v1_updated_score: <float> }
          # Downstream stubs still take a custid; derive from the key when
          # they are implemented (key.delete_prefix("customer:").delete_suffix(":object")).
          custid  = entry.is_a?(Hash) ? entry[:key] : entry
          v1_data = read_v1_source_data(custid)

          # Step 0: Idempotency fast-path
          # Must run before any writes, including the mark_in_progress write.
          return if already_migrated_and_current?(custid, v1_data)

          identifiers     = derive_identifiers(custid, v1_data)
          v2_fields       = transform_to_v2(custid, v1_data, identifiers)
          org, membership = generate_org_and_membership(custid, v1_data, identifiers)

          write_to_target_valkey(identifiers, v2_fields, org, membership)
          update_indexes(identifiers, v2_fields, org, membership)
          archive_v1_originals(custid, identifiers)
          mark_migration_status(identifiers, custid)

          log_debug 'Migrated customer', custid: redact(custid), objid: identifiers[:objid]
        end

        # ── Step 0: Idempotency fast-path ────────────────────────────────────

        # Returns true (skip) if the v2 record already exists with
        # migration_status == 'completed' AND v1 updated <= v2 migrated_at.
        #
        # This is defense-in-depth: the enqueuer filters already-migrated
        # custids, but messages can be redelivered.
        #
        # Implementation:
        #   1. Derive objid from v1_data[:created] + "customer:{custid}:object"
        #      (or accept it pre-derived from v1_data if enqueuer embeds it).
        #   2. target_v2_client.hget("customer:#{objid}:object", "migration_status")
        #   3. If == 'completed', compare v1 updated against migrated_at.
        #
        # @param custid [String] v1 customer ID (email-based)
        # @param v1_data [Hash] result of read_v1_source_data
        # @return [Boolean]
        #
        # TODO: implement. Caller is migrate_one; if this returns true, the
        # entire per-customer pipeline is skipped and the record is not touched.
        def already_migrated_and_current?(_custid, _v1_data)
          # TODO: derive tentative objid (same formula as derive_identifiers),
          # check target_v2_client.hget("customer:#{objid}:object", "migration_status"),
          # then compare timestamps. Return true to skip.
          false
        end

        # ── Step 1: Read v1 source data ───────────────────────────────────────

        # Reads the full v1 customer record from source Redis.
        #
        # Primary key: HGETALL "customer:{custid}:object"
        # Related keys (read separately or via pipeline):
        #   - "customer:{custid}:custom_domain" (ZRANGE — sorted set of domain names)
        #   - Counter externalization via session/metadata fields (if any remain
        #     in the hash; see CustomerTransformer::COUNTER_FIELDS for the list)
        #
        # Field inventory: scripts/upgrades/v0.24.5/01-customer/transform.rb
        #   CustomerTransformer::FIELD_TYPES (lines ~46-88) and
        #   CustomerTransformer::COUNTER_FIELDS (line ~41).
        #
        # Returns a hash with at minimum:
        #   { "custid" => custid, "created" => Float, "updated" => Float, ... }
        #
        # Raises HardInfrastructureError if source_v1_client is not reachable.
        # Raises RecordTransformError if HGETALL returns an empty hash
        # (key does not exist — could be already-deleted or typo in enqueuer).
        #
        # @param custid [String]
        # @return [Hash<String, String>] raw v1 string field values
        #
        # TODO: implement. Use source_v1_client. Wrap in rescue Redis::CannotConnectError
        # to raise HardInfrastructureError. For pipelining, see pipeline_enabled?
        # and transform.rb#pipeline_enabled? (line ~165-173).
        def read_v1_source_data(custid)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # Sort a custid array oldest-first by their `updated` field.
        # Called only if the enqueuer does not guarantee ordering.
        #
        # @param custids [Array<String>]
        # @return [Array<String>] sorted custids
        #
        # TODO: implement if needed. Requires reading v1 updated fields,
        # which is expensive (one HGET per custid). Prefer enqueuer-side sorting.
        def sort_by_updated_asc(custids)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 2: Derive identifiers ────────────────────────────────────────

        # Derives objid (UUIDv7) and extid deterministically from v1 source data.
        #
        # Algorithm (from enrich_with_identifiers.rb):
        #   - seed_key = "customer:#{custid}:object"
        #   - created_secs = v1_data["created"].to_f
        #   - objid = generate_uuid_v7_from(created_secs, seed_key: seed_key)
        #   - extid = derive_extid_from_uuid(objid, prefix: "ur")
        #
        # Reference: scripts/upgrades/v0.24.5/enrich_with_identifiers.rb
        #   IdentifierEnricher#generate_uuid_v7_from (line ~218)
        #   IdentifierEnricher#derive_extid_from_uuid (line ~251)
        #
        # WARNING: those methods are private instance methods on IdentifierEnricher.
        # They are NOT callable from here without refactoring.
        #
        # TODO (extraction): move generate_uuid_v7_from and derive_extid_from_uuid
        # to a shared module, e.g. Onetime::Migration::IdentifierDerivation,
        # so both the batch scripts and this worker can require_relative it.
        # Until then this method must inline or call-and-instantiate the class.
        #
        # Also derives the org_objid for the Organization synthesized in step 4.
        # org objid uses the same formula with seed_key = "customer:#{custid}:org".
        # org extid prefix = "on".
        #
        # Raises IdentifierDerivationError if `created` is missing or zero.
        #
        # @param custid [String]
        # @param v1_data [Hash<String, String>]
        # @return [Hash] { objid:, extid:, org_objid:, org_extid: }
        #
        # TODO: implement.
        def derive_identifiers(custid, v1_data)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 3: Transform v1 fields → v2 layout ───────────────────────────

        # Converts v1 raw string field values to Familia v2 JSON-encoded layout.
        #
        # What this must do (delegate to CustomerTransformer where possible):
        #   1. Counter externalization: extract secrets_created, secrets_burned,
        #      secrets_shared, emails_sent from the hash into a side structure.
        #      These become standalone String keys in step 5, NOT hash fields.
        #      Reference: CustomerTransformer::COUNTER_FIELDS (line ~41).
        #   2. State value renames:
        #      "viewed"    → "previewed"
        #      "received"  → "revealed"
        #      (applies to `state` field values, not field names)
        #   3. Inject objid + extid from identifiers into the field map.
        #   4. Serialize all fields via Familia::JsonSerializer.dump per field
        #      (see CustomerTransformer#serialize_for_v2, line ~181-189 of generate.rb
        #      or the equivalent in transform.rb).
        #   5. Inject v1_identifier = "customer:#{custid}:object" (for rollback ref).
        #
        # Encryption passthrough: customer records do not have encrypted payload
        # fields (secrets do). Copy passphrase/value/passphrase_encryption/
        # value_encryption verbatim; do NOT decrypt or re-encrypt.
        #
        # Reference: scripts/upgrades/v0.24.5/01-customer/transform.rb
        #   CustomerTransformer#transform_customer
        #   CustomerTransformer#serialize_for_v2
        #
        # Returns two values:
        #   v2_fields   [Hash<String, String>] — HMSET-ready, all values JSON-encoded
        #   counters    [Hash<String, Integer>] — { "secrets_created" => N, ... }
        #
        # @param custid [String]
        # @param v1_data [Hash<String, String>]
        # @param identifiers [Hash]
        # @return [Array(Hash, Hash)] [v2_fields, counters]
        #
        # TODO: implement. Instantiate or call CustomerTransformer methods.
        # Note CustomerTransformer was designed for file-based JSONL; it may
        # need an `in_memory` mode or method-level extraction.
        def transform_to_v2(custid, v1_data, identifiers)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 4: Generate Organization + OrganizationMembership ───────────

        # Synthesizes one Org and one OrganizationMembership (owner role) per customer.
        #
        # Organization field defaults (reference generate.rb#generate_organization):
        #   - objid:          identifiers[:org_objid]
        #   - extid:          identifiers[:org_extid]
        #   - display_name:   customer email (or domain-derived if available)
        #   - owner_id:       identifiers[:objid]   (customer objid)
        #   - billing_email:  customer email
        #   - planid:         v1 customer planid (inherit)
        #   - is_default:     true
        #   - created/updated: from v1 customer created/updated
        #   - migration_status: 'completed' (written at creation, not later)
        #
        # HMAC email_hash requires FEDERATION_SECRET env var.
        # If absent, set email_hash to nil and log a warning; do not fail the record.
        #
        # OrganizationMembership key pattern:
        #   org_membership:organization:{org_objid}:customer:{customer_objid}:org_membership:object
        # Fields: objid, organization_objid, customer_objid, role ("owner"), status ("active"),
        #         joined_at, updated_at.
        #
        # Reference: scripts/upgrades/v0.24.5/02-organization/generate.rb
        #   OrganizationGenerator#generate_organization (search for def generate_organization)
        #   OrganizationGenerator#generate_org_membership
        #   OrganizationGenerator::FIELD_TYPES (lines ~47-75)
        #   OrganizationGenerator::MEMBERSHIP_FIELD_TYPES (lines ~82-90)
        #
        # Both org and membership fields should be serialize_for_v2-encoded
        # (Familia::JsonSerializer.dump per field) before returning.
        #
        # @param custid [String]
        # @param v1_data [Hash<String, String>]
        # @param identifiers [Hash]
        # @return [Array(Hash, Hash)] [org_v2_fields, membership_v2_fields]
        #
        # TODO: implement. Instantiate or call OrganizationGenerator methods.
        def generate_org_and_membership(custid, v1_data, identifiers)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 5: Write to target Valkey DB 0 ──────────────────────────────

        # Writes customer, organization, and membership records to target Valkey.
        #
        # Commands (all to target_v2_client, DB 0):
        #   HMSET customer:{objid}:object              <v2_fields>
        #   SET   customer:{objid}:secrets_created     <N>   (and other counter fields)
        #   SET   customer:{objid}:secrets_burned      <N>
        #   SET   customer:{objid}:secrets_shared      <N>
        #   SET   customer:{objid}:emails_sent         <N>
        #   HMSET organization:{org_objid}:object      <org_v2_fields>
        #   HMSET org_membership:organization:{org_objid}:customer:{objid}:org_membership:object
        #         <membership_v2_fields>
        #
        # Pipelining: use target_v2_client.pipelined { |pipe| ... } when
        # pipeline_enabled? is true (OTS_MIGRATION_PIPELINE env var).
        #
        # Error mapping:
        #   Redis::CommandError matching HARD_ERROR_PATTERNS → HardInfrastructureError
        #   Any other Redis error on a single record → RecordWriteError
        #
        # Reference: scripts/upgrades/v0.24.5/load_keys.rb KeyLoader::HARD_ERROR_PATTERNS
        # (lines ~65-74) for which errors are hard vs soft.
        #
        # @param identifiers [Hash]
        # @param v2_fields [Hash<String, String>]
        # @param org_v2_fields [Hash<String, String>]
        # @param membership_v2_fields [Hash<String, String>]
        # @param counters [Hash<String, Integer>]
        #
        # TODO: implement.
        def write_to_target_valkey(identifiers, v2_fields, org_v2_fields, membership_v2_fields, counters = {})
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 6: Update indexes ────────────────────────────────────────────

        # Writes all index entries for customer and organization to target Valkey.
        #
        # Customer indexes (reference: 01-customer/create_indexes.rb):
        #   ZADD customer:instances              <created_score> <objid>
        #   HSET customer:email_index            <email>         <objid>
        #   HSET customer:extid_lookup           <extid>         <objid>
        #   HSET customer:objid_lookup           <objid>         <objid>   (legacy compat)
        #   SADD customer:role_index:{role}      <objid>
        #   INCRBY customer:secrets_created      <N>  (global aggregate counters)
        #   INCRBY customer:secrets_shared       <N>
        #   INCRBY customer:secrets_burned       <N>
        #   INCRBY customer:emails_sent          <N>
        #
        # Organization indexes (reference: 02-organization/create_indexes.rb):
        #   ZADD organization:instances          <created_score> <org_objid>
        #   HSET organization:email_index        <billing_email> <org_objid>
        #
        # OrganizationMembership indexes:
        #   ZADD org_membership:instances        <joined_at_score> <membership_key>
        #   SADD customer:{objid}:participations <org_objid>
        #
        # All ZADD scores are Float (Unix timestamp). INCRBY is additive to the
        # global aggregate — each migrated customer's counters contribute.
        #
        # Pipelining applies here the same as in write_to_target_valkey.
        #
        # TODO: implement. Confirm role value is in CustomerIndexCreator::VALID_ROLES
        # (01-customer/create_indexes.rb line ~45) before SADD; log and skip if not.
        def update_indexes(identifiers, v2_fields, org_v2_fields, membership_v2_fields)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 7: Archive v1 originals ─────────────────────────────────────

        # Archives v1 source records as _original_* sibling keys in DB 0.
        #
        # For each v1 key to archive:
        #   1. DUMP the key from source_v1_client
        #   2. RESTORE to target_v2_client with key "customer:{objid}:_original_object"
        #      TTL = 30 days in milliseconds = 2_592_000_000
        #      Flag: REPLACE (idempotent re-runs)
        #   3. Related keys (custom_domain sorted set, etc.) use matching
        #      _original_{suffix} key names.
        #
        # IMPORTANT: target DB must be the SAME DB as the v2 record (DB 0).
        # The _original_object hashkey in WithMigrationFields is declared on
        # the model, which means Familia computes the key relative to the model's
        # DB. Using a different DB would break _original_object.hgetall.
        #
        # Reference: scripts/upgrades/v0.24.5/enrich_with_original_record.rb
        #   header (lines ~1-50) for the target key pattern and TTL contract.
        #
        # If DUMP returns nil (key has already been deleted from source), log
        # a warning and skip — do not fail the record.
        #
        # @param custid [String] v1 customer ID
        # @param identifiers [Hash]
        #
        # TODO: implement. Use pipeline for DUMP fan-out if pipeline_enabled?.
        def archive_v1_originals(custid, identifiers)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Step 8: Mark migration status ─────────────────────────────────────

        # Marks the v2 customer record as migrated using the WithMigrationFields helpers.
        #
        # Preferred path: load the v2 record via Onetime::Customer.load(objid)
        # and call customer.mark_migrated!(v1_identifier) which writes:
        #   migration_status = 'completed'   (WithMigrationFields::MIGRATION_STATUS[:completed])
        #   migrated_at      = Time.now.to_f.to_s
        #   v1_identifier    = "customer:#{custid}:object"
        #
        # WARNING: the task brief says to write migration_status: 'migrated'.
        # The constant MIGRATION_STATUS[:completed] = 'completed'. Use the constant
        # and the helper (mark_migrated!); do NOT hardcode 'migrated'.
        # Similarly, 'in_progress' in the brief maps to MIGRATION_STATUS[:in_progress]
        # = 'migrating'. Use the constant.
        #
        # Reference: lib/onetime/models/features/with_migration_fields.rb
        #   WithMigrationFields::InstanceMethods#mark_migrated! (line ~96)
        #   WithMigrationFields::MIGRATION_STATUS (line ~29-36)
        #
        # If loading via model is too expensive (extra round-trip), fall back to
        # direct HSET:
        #   target_v2_client.hset("customer:#{objid}:object",
        #     "migration_status", Familia::JsonSerializer.dump("completed"),
        #     "migrated_at",      Familia::JsonSerializer.dump(Time.now.to_f))
        #
        # Apply the same mark for the org and membership records.
        #
        # @param identifiers [Hash]
        # @param custid [String]
        #
        # TODO: implement.
        def mark_migration_status(identifiers, custid)
          raise NotImplementedError, "#{__method__} is a skeleton — implement me"
        end

        # ── Failure handling ──────────────────────────────────────────────────

        # Per-record exception handler.
        #
        # Classifies the error, writes failure status to the v2 record if the
        # objid is known, then publishes a single-record DLQ message.
        #
        # Flow:
        #   1. Classify: HardInfrastructureError → re-raise (caller handles)
        #   2. Attempt to derive objid (may fail if error occurred in step 2)
        #   3. If objid known: HSET migration_status = 'failed' + migration_error
        #      on the v2 customer key (best-effort, do not raise on failure)
        #   4. Publish failure envelope to dlq.migration.customer.record
        #      Include: custid (redacted for logs), error class, truncated message,
        #      batch_id, Sentry event_id from Sentry.capture_exception.
        #   5. Log the error with structured fields.
        #
        # The per-record DLQ is NOT the AMQP dead-letter queue wired via
        # x-dead-letter-exchange. It is a separate named queue that a human or
        # retry job can drain. Publish via target_v2_client or a RabbitMQ channel
        # accessible from the worker — design TBD with enqueuer agent.
        #
        # TODO (enqueuer coordination): agree on the dlq.migration.customer.record
        # message schema and channel access pattern.
        #
        # @param entry [Hash] { key:, v1_updated_score: } from the batch payload
        # @param error [StandardError]
        # @param batch_id [String]
        def handle_per_record_failure(entry, error, batch_id)
          key = entry.is_a?(Hash) ? entry[:key] : entry.to_s

          # Sentry capture — do this first so event_id is available for DLQ payload
          sentry_event_id = capture_to_sentry(error, key: key, batch_id: batch_id)

          log_error 'Per-record migration failure',
            error,
            key: redact(key),
            batch_id: batch_id,
            sentry_event_id: sentry_event_id

          # TODO: attempt to write migration_status: 'failed' to v2 record.
          # Use mark_migration_failed_direct(entry, error) below.
          mark_migration_failed_direct(entry, error)

          # TODO: publish single-record failure to per-record DLQ.
          publish_to_record_dlq(entry, error, batch_id, sentry_event_id)
        rescue StandardError => ex
          # Failure handler must not raise — log and move on
          log_error 'Error in failure handler (swallowed)', ex, key: redact(key)
        end

        # Mark a v2 customer record as migration-failed via direct Redis write.
        # Used when per-record failure occurs; avoids loading the full model.
        #
        # Requires a tentative objid — if derive_identifiers itself failed, objid
        # may be unknown. In that case, skip the write and only log.
        #
        # TODO: implement. Call mark_migration_failed! on the model if loadable,
        # or HSET directly: migration_status = 'failed', migration_error = truncated msg.
        def mark_migration_failed_direct(entry, error)
          # TODO: implement
        end

        # Publish a single-record failure payload to the per-record DLQ.
        # NOT the AMQP x-dead-letter-exchange — this is an application-level DLQ.
        #
        # TODO: implement. Schema TBD with enqueuer agent.
        # Minimum payload: { key:, v1_updated_score:, error_class:, error_message:,
        #                    batch_id:, sentry_event_id:, failed_at: }
        def publish_to_record_dlq(entry, error, batch_id, sentry_event_id)
          # TODO: implement
        end

        # ── Redis client accessors ────────────────────────────────────────────

        # Lazy accessor for v1 source Redis client.
        # URL from V1_REDIS_URL env var.
        # Raises HardInfrastructureError on connection failure (wrapped by callers).
        #
        # TODO: implement. Use Redis.new(url: ...) matching create_redis_client
        # pattern in services/redis_key_migrator.rb (line ~613).
        def source_v1_client
            # TODO: Redis.new(url: ENV.fetch('V1_REDIS_URL'), ...)
            @source_v1_client ||= raise NotImplementedError, 'source_v1_client not implemented'
        end

        # Lazy accessor for v2 target Valkey client (DB 0).
        # Uses VALKEY_URL (or REDIS_URL fallback) env var.
        # In most runtime paths, Familia.dbclient already points here —
        # check whether reusing it avoids a second connection.
        #
        # TODO: implement.
        def target_v2_client
            # TODO: Redis.new(url: ENV.fetch('VALKEY_URL', ENV['REDIS_URL']), db: 0, ...)
            @target_v2_client ||= raise NotImplementedError, 'target_v2_client not implemented'
        end

        # ── Helpers ───────────────────────────────────────────────────────────

        # Returns true if OTS_MIGRATION_PIPELINE env var is truthy.
        # Memoized; ENV is read once.
        def pipeline_enabled?
          return @pipeline_enabled if defined?(@pipeline_enabled)

          raw               = ENV.fetch('OTS_MIGRATION_PIPELINE', '').strip.downcase
          @pipeline_enabled = !(raw.empty? || %w[0 false no off].include?(raw))
        end

        # Redact PII from custid for log output.
        # Customer IDs are email addresses in v1; log only the domain portion.
        def redact(custid)
          return '[nil]' if custid.nil?

          parts = custid.to_s.split('@', 2)
          parts.length == 2 ? "@#{parts.last}" : custid[0, 6] + '...'
        end

        # Capture exception to Sentry with migration context tags.
        # Returns Sentry event_id string, or nil if Sentry is not configured.
        def capture_to_sentry(error, **tags)
          return unless defined?(Sentry)

          Sentry.capture_exception(error, tags: { worker: 'CustomerMigrationWorker', **tags })
          nil # Sentry.capture_exception returns an Event, not an id string in all versions
        rescue StandardError
          nil
        end

        # Maps hard Redis error messages to HardInfrastructureError.
        # Reference: load_keys.rb KeyLoader::HARD_ERROR_PATTERNS (line ~65-74).
        HARD_ERROR_PATTERNS = [
          /\AWRONGTYPE/,
          /\ANOAUTH/,
          /\AREADONLY/,
          /\ALOADING/,
          /\ACLUSTERDOWN/,
          /\AMISCONF/,
          /\AOOM\b/,
          /DUMP payload version or checksum/,
        ].freeze
        private_constant :HARD_ERROR_PATTERNS

        def hard_redis_error?(ex)
          HARD_ERROR_PATTERNS.any? { |pattern| pattern.match?(ex.message.to_s) }
        end
      end
    end
  end
end
