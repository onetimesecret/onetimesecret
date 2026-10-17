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
        #   - Stale index entries (target doesn't exist) are removed
        #   - Mismatched entries (the target no longer holds the indexed
        #     value) are removed and the target's current value is indexed
        #   - Missing index entries (object exists but no index) are re-added
        #
        # Conflicting entries (an object whose value the index assigns to
        # another existing object) are reported and never repaired.
        #
        # Value forms. Familia stores a Horreum string field JSON-encoded
        # ("\"a@b.example\"") but keys a unique index by the decoded value
        # (field_value.to_s) and stores the identifier raw; Familia 2.9.x
        # stored the identifier JSON-quoted, which the finders still accept.
        # Fields are decoded before they are compared with, or written as, an
        # index key, and both identifier forms are accepted. Repairs go through
        # Familia's ownership-checked HashKey#claim_field and #release_field,
        # which write the same forms Familia's own index writes do and never
        # overwrite or delete an entry that another record holds.
        #
        # Oneshot candidate: daily cron, no app-state coupling.
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
              redis          = Familia.dbclient
              repair         = auto_repair?(JOB_KEY)
              indexes_report = {}

              INDEXES.each do |label, index_key, prefix, field_name|
                indexes_report[label] = reconcile_index(
                  redis, index_key, prefix, field_name, repair
                )
              end

              report[:indexes]     = indexes_report
              report[:auto_repair] = repair
            end

            # Forward check: verify each index entry points to a valid object
            # Reverse check: verify each object has an index entry
            def reconcile_index(redis, index_key, prefix, field_name, repair)
              index                 = index_hashkey(index_key)
              stale_entries         = 0
              mismatched_entries    = 0
              missing_entries       = 0
              conflicting_entries   = 0
              repaired_stale        = 0
              repaired_missing      = 0
              repaired_mismatched   = 0
              entries_checked       = 0

              # Forward check: scan index entries
              redis.hscan_each(index_key, count: MaintenanceJob::SCAN_COUNT) do |field, value|
                entries_checked += 1
                identifier       = index_identifier(value)
                target_key       = backing_key(prefix, identifier)

                unless redis.exists?(target_key)
                  stale_entries  += 1
                  repaired_stale += 1 if repair && index.release_field(field, identifier) == 1
                  next
                end

                # Verify the field on the target matches the index key.
                # A mismatch means the object's field was updated but the
                # old index entry wasn't cleaned up. Repair by removing
                # the stale key and ensuring the current value is indexed.
                current = index_field_for(redis.hget(target_key, field_name))
                next if current.nil? || current == field

                mismatched_entries += 1
                next unless repair && index.release_field(field, identifier) == 1

                repaired_mismatched += 1
                # claim_field leaves the value alone when another record
                # holds it; the reverse check reports that as a conflict.
                index.claim_field(current, identifier)
              end

              # Reverse check: scan objects and verify index entry exists
              objects_checked = 0
              redis.scan_each(match: model_scan_pattern(prefix), count: MaintenanceJob::SCAN_COUNT) do |key|
                objects_checked += 1
                field_value      = index_field_for(redis.hget(key, field_name))
                next unless field_value

                # Extract the identifier from the key (strips prefix and :object suffix)
                identifier = extract_identifier(prefix, key)
                next unless identifier

                holder = index_identifier(redis.hget(index_key, field_value))
                if holder
                  conflicting_entries += 1 if holder != identifier && redis.exists?(backing_key(prefix, holder))
                  next
                end

                missing_entries  += 1
                # claim_field returns :created or :owned, or the identifier of
                # a record that indexed the value after the HGET above.
                repaired_missing += 1 if repair && index.claim_field(field_value, identifier).is_a?(Symbol)
              end

              {
                entries_checked: entries_checked,
                stale_entries: stale_entries,
                mismatched_entries: mismatched_entries,
                objects_checked: objects_checked,
                missing_entries: missing_entries,
                conflicting_entries: conflicting_entries,
                repaired_stale: repaired_stale,
                repaired_missing: repaired_missing,
                repaired_mismatched: repaired_mismatched,
              }
            end

            # The class-level unique index as Familia declares it
            # (`class_hashkey ..., reference: true`), so a claim stores the
            # identifier raw and a release also matches the JSON-quoted
            # Familia 2.9.x form of the same identifier.
            def index_hashkey(index_key)
              Familia::HashKey.new(index_key, reference: true)
            end

            # The index key Familia writes for a stored Horreum field: the
            # decoded value's #to_s. nil when the field is unset or blank,
            # which has no index entry.
            def index_field_for(stored)
              value = parse_redis_value(stored)
              return nil if value.nil?

              field = value.to_s
              field.empty? ? nil : field
            end

            # The identifier an index entry holds, raw or in the JSON-quoted
            # Familia 2.9.x form (stripped the way Familia's finders strip it).
            # nil for an absent entry.
            def index_identifier(stored)
              Familia.legacy_json_encoded?(stored) ? stored[1..-2] : stored
            end
          end
        end
      end
    end
  end
end
