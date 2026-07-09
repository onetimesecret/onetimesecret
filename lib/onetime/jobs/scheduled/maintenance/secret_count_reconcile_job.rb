# lib/onetime/jobs/scheduled/maintenance/secret_count_reconcile_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Reconciles each customer's `secrets_active` counter against the true
        # count of live secrets they own (issue #60).
        #
        # ## Why this job is the PRIMARY correctness mechanism
        #
        # `secrets_active` is incremented once per secret create at the
        # `Receipt.spawn_pair` chokepoint and decremented once per early
        # destruction at `Secret#destroy!` (reveal / burn / admin delete — see
        # Customer::Features::CounterFields). The remaining drift source is TTL
        # expiry: Redis drops the key silently, no application code runs, so
        # the counter can still OVER-count between runs. This job recomputes
        # the truth from the datastore and SETs the counter back to it — the
        # increment/decrement pair keeps the value approximately fresh; this
        # recount makes it correct.
        #
        # ## Method: one bounded cursor SCAN, off the request path (#2211)
        #
        # It performs a single non-blocking cursor SCAN over every
        # `secret:*:object` key (COUNT-bounded per round-trip, never a blocking
        # KEYS / unbounded SMEMBERS) and tallies live secrets per `owner_id` —
        # the same grouping the colonel users list SCAN used to do per request,
        # now moved here and, crucially, with NO 10k cap (the point of #60:
        # correct beyond 10k secrets per owner). It then SETs every known
        # customer's counter to its tally (0 when the owner has no live secrets
        # left), which is exactly the drift-correcting recount.
        #
        # The same `reconcile` is used to BACKFILL all customers at rollout —
        # `bin/ots migrations backfill-secret-counts --run` calls it directly.
        # A daily fresh recount and a one-time backfill are the identical
        # operation, so there is one implementation.
        #
        # ## Configuration
        #
        # Deliberately has NO dedicated enabled/cron config key. Per the epic's
        # config-surface rule, a value operators do not need to tune should be a
        # sensible hardcoded default rather than a new key threaded through
        # YAML + Ruby DEFAULTS + Zod contracts/shapes + .env.reference. The
        # recount is always-safe (idempotent SET to the true value), so it is
        # gated only behind the existing `jobs.maintenance.enabled` master
        # toggle and runs on a fixed daily schedule. To turn it off, disable the
        # maintenance master toggle (or run the scheduler without maintenance).
        #
        class SecretCountReconcileJob < MaintenanceJob
          JOB_KEY = 'secret_count_reconcile'

          # Fixed daily schedule (04:30 — offset from the 04:00 index_rebuild so
          # the two daily maintenance scans do not start in lockstep). Hardcoded
          # on purpose; see the class-level "Configuration" note.
          CRON = '30 4 * * *'

          # Sentinel owner_id for anonymous / ownerless secrets — no per-customer
          # counter exists for these, so they are not tallied (mirrors the old
          # per-request SCAN, which only grouped real owner_ids).
          ANON_OWNER = 'anon'

          class << self
            def schedule(scheduler)
              return unless reconcile_enabled?

              scheduler_logger.info "[SecretCountReconcileJob] Scheduling with cron: #{CRON}"

              cron(scheduler, CRON) do
                with_stats('SecretCountReconcileJob') do |report|
                  report.merge!(reconcile)
                end
              end
            end

            # Recount live secrets per owner and SET each customer's
            # secrets_active counter to the truth. Shared by the daily schedule
            # above and the `migrations backfill-secret-counts` CLI (backfill).
            #
            # @param dry_run [Boolean] when true, compute and report the
            #   corrections without writing any counter.
            # @param logger [#info, nil] optional logger for a JSON summary line.
            # @return [Hash] structured report of the run.
            def reconcile(dry_run: false, logger: nil)
              redis = Familia.dbclient

              tally, secrets_scanned = tally_live_secrets_by_owner(redis)
              processed, corrected   = apply_counts(redis, tally, dry_run)

              report = {
                secrets_scanned: secrets_scanned,
                owners_with_live_secrets: tally.size,
                customers_processed: processed,
                customers_corrected: corrected,
                dry_run: dry_run,
              }
              logger&.info("[SecretCountReconcileJob] #{JSON.generate(report)}")
              report
            end

            private

            def reconcile_enabled?
              maintenance_config['enabled'] == true
            end

            # Phase 1 — bounded cursor SCAN of all secret hashes, tallying live
            # secrets per owner_id. Reading only the owner_id field (HGET) avoids
            # loading/decrypting the secret body. Keys returned by SCAN exist at
            # scan time; a nil HGET (raced expiry) is simply skipped.
            #
            # @return [Array(Hash, Integer)] the owner_id => count tally and the
            #   number of secret keys scanned.
            def tally_live_secrets_by_owner(redis)
              tally           = Hash.new(0)
              secrets_scanned = 0

              redis.scan_each(match: model_scan_pattern('secret'), count: MaintenanceJob::SCAN_COUNT) do |key|
                secrets_scanned += 1
                owner_id = parse_redis_value(redis.hget(key, 'owner_id'))
                next if owner_id.nil?

                owner_id = owner_id.to_s
                next if owner_id.empty? || owner_id == ANON_OWNER

                tally[owner_id] += 1
              end

              [tally, secrets_scanned]
            end

            # Phase 2 — SET every customer's secrets_active to its true live
            # count. Processes the UNION of (a) all known customers
            # (Customer.instances) so up-drift is corrected even down to zero for
            # owners whose secrets have all expired, and (b) any owner_id present
            # in the tally (defensive coverage for a live-secret owner somehow
            # missing from the instances set). Only writes on an actual change.
            #
            # @return [Array(Integer, Integer)] processed count and corrected
            #   (changed) count.
            def apply_counts(redis, tally, dry_run)
              objids = Set.new(tally.keys)
              zscan_each(redis, Onetime::Customer.instances.dbkey) { |objid| objids << objid }

              processed = 0
              corrected = 0

              objids.each do |objid|
                objid = objid.to_s
                next if objid.empty?

                processed += 1
                true_count = tally[objid] || 0
                cust       = Onetime::Customer.new(objid: objid)
                next if cust.secrets_active.to_i == true_count

                corrected += 1
                cust.secrets_active.reset(true_count) unless dry_run
              end

              [processed, corrected]
            end
          end
        end
      end
    end
  end
end
