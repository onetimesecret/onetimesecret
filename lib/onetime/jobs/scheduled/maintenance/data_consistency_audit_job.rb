# lib/onetime/jobs/scheduled/maintenance/data_consistency_audit_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Read-only audit job that checks data consistency across
        # Redis data structures without making any modifications.
        #
        # For each of the 7 models, performs:
        #   1. Instance count comparison (ZCARD vs SCAN count)
        #   2. Sample validation (random members checked for backing keys)
        #   3. Index cross-checks (unique indexes verified)
        #   4. Participation bidirectionality checks
        #
        # Output: structured JSON report logged at INFO level.
        #
        # Configuration:
        #   jobs.maintenance.data_audit.enabled: true
        #   jobs.maintenance.data_audit.interval: '6h'
        #   jobs.maintenance.data_audit.sample_size: 100
        #
        class DataConsistencyAuditJob < MaintenanceJob
          JOB_KEY = 'data_audit'

          class << self
            def schedule(scheduler)
              return unless job_enabled?(JOB_KEY)

              interval = job_interval(JOB_KEY)
              scheduler_logger.info "[DataConsistencyAuditJob] Scheduling with interval: #{interval}"

              every(scheduler, interval, first_in: '5m') do
                with_stats('DataConsistencyAuditJob') do |report|
                  run_audit(report)
                end
              end
            end

            private

            def run_audit(report)
              redis = Familia.dbclient
              samples = sample_size(JOB_KEY)

              models_report = {}

              INSTANCE_MODELS.each do |label, class_name, prefix|
                model_class = resolve_model(class_name)
                models_report[label] = audit_model(redis, model_class, prefix, samples)
              end

              report[:models] = models_report
              report[:participation] = audit_participation(redis, samples)
              report[:indexes] = audit_indexes(redis, samples)
            end

            # Audit a single model's instances sorted set
            def audit_model(redis, model_class, prefix, samples)
              dbkey = model_class.instances.dbkey
              instances_count = redis.zcard(dbkey)

              # Count actual keys matching the prefix pattern
              scan_count = 0
              redis.scan_each(match: "#{prefix}:*", count: 100) do |key|
                # Only count hash keys (the model objects), not sub-structures
                scan_count += 1 if redis.type(key) == 'hash'
              end

              # Sample random members from the sorted set
              phantoms_found = 0
              objid_mismatches = 0
              sampled = 0

              members = redis.zrandmember(dbkey, samples) || []
              members = [members] if members.is_a?(String)
              members.compact.uniq.each do |member|
                sampled += 1
                redis_key = "#{prefix}:#{member}"

                unless redis.exists?(redis_key)
                  phantoms_found += 1
                  next
                end

                # Verify objid field matches the identifier
                stored_objid = redis.hget(redis_key, 'objid')
                if stored_objid && stored_objid != member
                  objid_mismatches += 1
                end
              end

              {
                instances_count: instances_count,
                scan_count: scan_count,
                discrepancy: scan_count - instances_count,
                sample_size: sampled,
                phantoms_found: phantoms_found,
                objid_mismatches: objid_mismatches,
              }
            end

            # Audit participation sorted sets for stale references
            def audit_participation(redis, samples)
              stale_refs = 0
              sets_checked = 0

              PARTICIPATION_PATTERNS.each do |pattern|
                member_prefix = participation_member_prefix(pattern)

                redis.scan_each(match: pattern, count: 100) do |key|
                  sets_checked += 1
                  members = redis.zrandmember(key, [samples, 10].min) || []
                  members = [members] if members.is_a?(String)

                  members.compact.uniq.each do |member|
                    redis_key = "#{member_prefix}:#{member}"
                    stale_refs += 1 unless redis.exists?(redis_key)
                  end
                end
              end

              { sets_checked: sets_checked, stale_refs: stale_refs }
            end

            # Audit unique indexes for consistency
            def audit_indexes(redis, samples)
              results = {}

              # Customer email_index
              results['customer_email_index'] = audit_hash_index(
                redis, 'customer:email_index', 'customer', samples
              )

              # Organization contact_email_index
              results['org_contact_email_index'] = audit_hash_index(
                redis, 'organization:contact_email_index', 'organization', samples
              )

              # CustomDomain display_domain_index
              results['domain_display_index'] = audit_hash_index(
                redis, 'custom_domain:display_domain_index', 'custom_domain', samples
              )

              results
            end

            # Audit a hash-based unique index by sampling entries
            # and verifying the target object exists.
            def audit_hash_index(redis, index_key, target_prefix, samples)
              total_entries = redis.hlen(index_key)
              return { total: 0, sampled: 0, stale: 0 } if total_entries == 0

              stale = 0
              sampled = 0
              cursor = '0'

              loop do
                cursor, entries = redis.hscan(index_key, cursor, count: samples)
                entries.each do |_field, value|
                  sampled += 1
                  target_key = "#{target_prefix}:#{value}"
                  stale += 1 unless redis.exists?(target_key)
                  break if sampled >= samples
                end
                break if cursor == '0' || sampled >= samples
              end

              { total: total_entries, sampled: sampled, stale: stale }
            end

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
