# lib/onetime/jobs/scheduled/maintenance/instances_rebuild_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Rebuilds class-level instances sorted sets by scanning all
        # existing model keys and reconciling against the current set.
        #
        # Uses a merge approach (not atomic RENAME) to avoid losing
        # entries added by application code during the scan window:
        #   1. SCAN all {prefix}:* hash keys
        #   2. Add any missing members to the instances sorted set
        #   3. Remove phantom members (in instances but key gone)
        #   4. Safety check: abort if diff > 20% of total
        #
        # This is the most invasive maintenance job — run weekly.
        #
        # Configuration:
        #   jobs.maintenance.instances_rebuild.enabled: true
        #   jobs.maintenance.instances_rebuild.cron: '0 3 * * 0'
        #   jobs.maintenance.instances_rebuild.auto_repair: false
        #
        class InstancesRebuildJob < MaintenanceJob
          JOB_KEY = 'instances_rebuild'

          # If the diff between scanned keys and current instances
          # exceeds this fraction, abort the rebuild as a safety check.
          DRIFT_THRESHOLD = 0.20

          # Known hash-typed sub-structure suffixes to exclude when scanning
          # for model instance keys. These are indexes and metadata hashes
          # that share the model prefix but are not model instances.
          SUB_STRUCTURE_SUFFIXES = %w[
            email_index
            contact_email_index
            display_domain_index
          ].freeze

          class << self
            def schedule(scheduler)
              return unless job_enabled?(JOB_KEY)

              cron_pattern = job_cron(JOB_KEY)
              scheduler_logger.info "[InstancesRebuildJob] Scheduling with cron: #{cron_pattern}"

              cron(scheduler, cron_pattern) do
                with_stats('InstancesRebuildJob') do |report|
                  rebuild_instances(report)
                end
              end
            end

            private

            def rebuild_instances(report)
              redis         = Familia.dbclient
              repair        = auto_repair?(JOB_KEY)
              models_report = {}

              MaintenanceJob::INSTANCE_MODELS.each do |label, class_name, prefix|
                model_class          = resolve_model(class_name)
                dbkey                = model_class.instances.dbkey
                models_report[label] = reconcile_model(redis, dbkey, prefix, repair)
              end

              report[:models]      = models_report
              report[:auto_repair] = repair
            end

            def reconcile_model(redis, instances_key, prefix, repair)
              # Step 1: Collect all existing hash keys for this prefix.
              # In-memory Sets are acceptable here — model counts are bounded
              # (tens of thousands max) and diff computation requires both sets.
              scanned_ids = Set.new
              redis.scan_each(match: "#{prefix}:*", count: MaintenanceJob::SCAN_COUNT) do |key|
                next unless redis.type(key) == 'hash'

                identifier = key.sub("#{prefix}:", '')
                # Skip known sub-structure keys (e.g., "customer:email_index")
                next if SUB_STRUCTURE_SUFFIXES.include?(identifier)

                scanned_ids << identifier
              end

              # Step 2: Collect all current instances members
              current_ids = Set.new
              zscan_each(redis, instances_key) do |member|
                current_ids << member
              end

              # Step 3: Compute diff
              missing_from_instances = scanned_ids - current_ids
              phantom_in_instances   = current_ids - scanned_ids

              total      = [scanned_ids.size, current_ids.size].max
              diff_count = missing_from_instances.size + phantom_in_instances.size

              result = {
                scanned_keys: scanned_ids.size,
                current_members: current_ids.size,
                missing_from_instances: missing_from_instances.size,
                phantom_in_instances: phantom_in_instances.size,
                repaired: false,
                aborted: false,
              }

              # Safety check: abort if drift is too large
              if total > 0 && diff_count.to_f / total > DRIFT_THRESHOLD
                scheduler_logger.error "[InstancesRebuildJob] Drift too large for #{prefix}: " \
                                       "#{diff_count}/#{total} (#{(diff_count.to_f / total * 100).round(1)}%) exceeds " \
                                       "#{(DRIFT_THRESHOLD * 100).round}% threshold — aborting"
                result[:aborted] = true
                return result
              end

              if repair && (missing_from_instances.any? || phantom_in_instances.any?)
                now = Familia.now.to_f

                # Add missing members
                if missing_from_instances.any?
                  missing_from_instances.each_slice(100) do |batch|
                    args = batch.flat_map { |id| [now, id] }
                    redis.zadd(instances_key, args)
                  end
                end

                # Remove phantoms
                if phantom_in_instances.any?
                  phantom_in_instances.each_slice(100) do |batch|
                    redis.zrem(instances_key, batch)
                  end
                end

                result[:repaired] = true
              end

              result
            end
          end
        end
      end
    end
  end
end
