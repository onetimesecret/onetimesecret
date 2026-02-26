# lib/onetime/jobs/scheduled/maintenance/index_rebuild_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Reconciles unique hash-based indexes by verifying that
        # each index entry points to a valid object and vice versa.
        #
        # Indexes checked:
        #   - Customer.email_index (email → objid)
        #   - Organization.contact_email_index (email → objid)
        #   - CustomDomain.display_domain_index (domain → objid)
        #
        # When auto_repair is enabled:
        #   - Stale index entries (target doesn't exist) are removed via HDEL
        #   - Missing index entries (object exists but no index) are re-added
        #
        # Configuration:
        #   jobs.maintenance.index_rebuild.enabled: true
        #   jobs.maintenance.index_rebuild.cron: '0 4 * * *'
        #   jobs.maintenance.index_rebuild.auto_repair: false
        #
        class IndexRebuildJob < MaintenanceJob
          JOB_KEY = 'index_rebuild'

          # Index definitions: [label, index_key, target_prefix, field_name]
          # field_name is the hash field on the target object that should
          # match the index key (e.g., 'email' on Customer)
          INDEXES = [
            ['customer_email', 'customer:email_index', 'customer', 'email'],
            ['org_contact_email', 'organization:contact_email_index', 'organization', 'contact_email'],
            ['domain_display', 'custom_domain:display_domain_index', 'custom_domain', 'display_domain'],
          ].freeze

          class << self
            def schedule(scheduler)
              return unless job_enabled?(JOB_KEY)

              cron_pattern = job_cron(JOB_KEY)
              scheduler_logger.info "[IndexRebuildJob] Scheduling with cron: #{cron_pattern}"

              cron(scheduler, cron_pattern) do
                with_stats('IndexRebuildJob') do |report|
                  reconcile_indexes(report)
                end
              end
            end

            private

            def reconcile_indexes(report)
              redis = Familia.dbclient
              repair = auto_repair?(JOB_KEY)
              indexes_report = {}

              INDEXES.each do |label, index_key, prefix, field_name|
                indexes_report[label] = reconcile_index(
                  redis, index_key, prefix, field_name, repair
                )
              end

              report[:indexes] = indexes_report
              report[:auto_repair] = repair
            end

            # Forward check: verify each index entry points to a valid object
            # Reverse check: verify each object has an index entry
            def reconcile_index(redis, index_key, prefix, field_name, repair)
              stale_entries = 0
              mismatched_entries = 0
              missing_entries = 0
              repaired_stale = 0
              repaired_missing = 0
              entries_checked = 0

              # Forward check: scan index entries
              redis.hscan_each(index_key, count: 100) do |field, value|
                entries_checked += 1
                target_key = "#{prefix}:#{value}"

                unless redis.exists?(target_key)
                  stale_entries += 1
                  if repair
                    redis.hdel(index_key, field)
                    repaired_stale += 1
                  end
                  next
                end

                # Verify the field on the target matches the index key
                stored_field = redis.hget(target_key, field_name)
                if stored_field && stored_field != field
                  mismatched_entries += 1
                end
              end

              # Reverse check: scan objects and verify index entry exists
              objects_checked = 0
              redis.scan_each(match: "#{prefix}:*", count: 100) do |key|
                next unless redis.type(key) == 'hash'

                objects_checked += 1
                field_value = redis.hget(key, field_name)
                next unless field_value && !field_value.empty?

                # Extract the identifier from the key
                identifier = key.sub("#{prefix}:", '')
                indexed_value = redis.hget(index_key, field_value)

                if indexed_value.nil?
                  missing_entries += 1
                  if repair
                    redis.hset(index_key, field_value, identifier)
                    repaired_missing += 1
                  end
                end
              end

              {
                entries_checked: entries_checked,
                stale_entries: stale_entries,
                mismatched_entries: mismatched_entries,
                objects_checked: objects_checked,
                missing_entries: missing_entries,
                repaired_stale: repaired_stale,
                repaired_missing: repaired_missing,
              }
            end
          end
        end
      end
    end
  end
end
