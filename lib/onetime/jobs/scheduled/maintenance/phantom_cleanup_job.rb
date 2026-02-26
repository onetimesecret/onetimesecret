# lib/onetime/jobs/scheduled/maintenance/phantom_cleanup_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Removes phantom members from sorted sets — entries that
        # reference Redis keys which no longer exist.
        #
        # This is the most common form of data drift: when a key
        # expires via TTL or is destroyed without cleaning up its
        # sorted set membership, the identifier lingers as a phantom.
        #
        # Scans both class-level instances sorted sets (7 models)
        # and participation sorted sets (organization:*:members, etc.).
        #
        # Configuration:
        #   jobs.maintenance.phantom_cleanup.enabled: true
        #   jobs.maintenance.phantom_cleanup.interval: '1h'
        #   jobs.maintenance.phantom_cleanup.batch_size: 500
        #   jobs.maintenance.phantom_cleanup.auto_repair: false
        #
        class PhantomCleanupJob < MaintenanceJob
          JOB_KEY = 'phantom_cleanup'

          class << self
            def schedule(scheduler)
              return unless job_enabled?(JOB_KEY)

              interval = job_interval(JOB_KEY)
              scheduler_logger.info "[PhantomCleanupJob] Scheduling with interval: #{interval}"

              every(scheduler, interval, first_in: '2m') do
                with_stats('PhantomCleanupJob') do |report|
                  cleanup_phantoms(report)
                end
              end
            end

            private

            def cleanup_phantoms(report)
              redis = Familia.dbclient
              repair = auto_repair?(JOB_KEY)
              limit = batch_size(JOB_KEY)

              models_report = {}
              total_phantoms = 0
              total_removed = 0

              INSTANCE_MODELS.each do |label, class_name, prefix|
                model_class = resolve_model(class_name)
                dbkey = model_class.instances.dbkey
                phantoms = scan_phantoms_in_sorted_set(redis, dbkey, prefix, limit)

                removed = 0
                if repair && phantoms.any?
                  removed = phantoms.size
                  redis.zrem(dbkey, phantoms)
                end

                total_phantoms += phantoms.size
                total_removed += removed

                models_report[label] = {
                  phantoms_found: phantoms.size,
                  removed: removed,
                }
              end

              participation_report = {}
              PARTICIPATION_PATTERNS.each do |pattern|
                result = scan_participation_phantoms(redis, pattern, repair, limit)
                participation_report[pattern] = result
                total_phantoms += result[:phantoms_found]
                total_removed += result[:removed]
              end

              report[:models] = models_report
              report[:participation] = participation_report
              report[:total_phantoms] = total_phantoms
              report[:total_removed] = total_removed
              report[:auto_repair] = repair
            end

            # Scan a sorted set for members whose backing hash key
            # does not exist. Returns an array of phantom member IDs.
            def scan_phantoms_in_sorted_set(redis, sorted_set_key, prefix, limit)
              phantoms = []
              batch = []

              zscan_each(redis, sorted_set_key) do |member|
                batch << member

                if batch.size >= PIPELINE_BATCH
                  phantoms.concat(check_batch(redis, batch, prefix))
                  batch = []
                  break if phantoms.size >= limit
                end
              end

              # Process remaining batch
              if batch.any? && phantoms.size < limit
                phantoms.concat(check_batch(redis, batch, prefix))
              end

              phantoms.take(limit)
            end

            # Check a batch of members against their backing hash keys.
            # Returns members whose keys do not exist.
            def check_batch(redis, members, prefix)
              keys = members.map { |m| "#{prefix}:#{m}" }
              results = pipeline_exists(redis, keys)

              phantoms = []
              members.each_with_index do |member, idx|
                phantoms << member unless results[idx]
              end
              phantoms
            end

            # Scan participation sorted sets matching a glob pattern
            # and check each member for a valid backing key.
            def scan_participation_phantoms(redis, pattern, repair, limit)
              total_phantoms = 0
              total_removed = 0
              keys_scanned = 0

              # Determine the prefix for members based on the pattern suffix
              member_prefix = participation_member_prefix(pattern)

              redis.scan_each(match: pattern, count: 100) do |key|
                keys_scanned += 1
                phantoms = []

                zscan_each(redis, key) do |member|
                  redis_key = "#{member_prefix}:#{member}"
                  phantoms << member unless redis.exists?(redis_key)
                  break if phantoms.size >= limit
                end

                total_phantoms += phantoms.size

                if repair && phantoms.any?
                  redis.zrem(key, phantoms)
                  total_removed += phantoms.size
                end
              end

              { keys_scanned: keys_scanned, phantoms_found: total_phantoms, removed: total_removed }
            end

            # Map participation pattern suffix to the member's Redis prefix.
            # e.g., organization:*:members → customer, organization:*:domains → custom_domain
            def participation_member_prefix(pattern)
              case pattern
              when /members$/   then 'customer'
              when /domains$/   then 'custom_domain'
              when /receipts$/  then 'receipt'
              else 'unknown'
              end
            end
          end
        end
      end
    end
  end
end
