# lib/onetime/jobs/scheduled/maintenance/participation_gc_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Garbage-collects stale members from per-instance participation
        # sorted sets: organization:*:members, organization:*:domains,
        # organization:*:receipts, custom_domain:*:receipts.
        #
        # Also handles expired OrganizationMembership records in
        # organization:*:pending_invitations.
        #
        # Configuration:
        #   jobs.maintenance.participation_gc.enabled: true
        #   jobs.maintenance.participation_gc.cron: '0 5 * * *'
        #   jobs.maintenance.participation_gc.batch_size: 500
        #   jobs.maintenance.participation_gc.auto_repair: false
        #
        class ParticipationGCJob < MaintenanceJob
          JOB_KEY = 'participation_gc'

          INVITATION_PATTERN = 'organization:*:pending_invitations'

          class << self
            def schedule(scheduler)
              return unless job_enabled?(JOB_KEY)

              cron_pattern = job_cron(JOB_KEY)
              scheduler_logger.info "[ParticipationGCJob] Scheduling with cron: #{cron_pattern}"

              cron(scheduler, cron_pattern) do
                with_stats('ParticipationGCJob') do |report|
                  gc_participations(report)
                end
              end
            end

            private

            def gc_participations(report)
              redis = Familia.dbclient
              repair = auto_repair?(JOB_KEY)
              limit = batch_size(JOB_KEY)

              participation_report = {}

              PARTICIPATION_PATTERNS.each do |pattern|
                participation_report[pattern] = gc_pattern(redis, pattern, repair, limit)
              end

              invitation_report = gc_pending_invitations(redis, repair, limit)

              report[:participation] = participation_report
              report[:invitations] = invitation_report
              report[:auto_repair] = repair
            end

            # GC stale members from sorted sets matching a glob pattern
            def gc_pattern(redis, pattern, repair, limit)
              member_prefix = participation_member_prefix(pattern)
              total_stale = 0
              total_removed = 0
              keys_scanned = 0

              redis.scan_each(match: pattern, count: SCAN_COUNT) do |key|
                keys_scanned += 1
                stale_members = []

                zscan_each(redis, key) do |member|
                  redis_key = "#{member_prefix}:#{member}"
                  stale_members << member unless redis.exists?(redis_key)
                  break if stale_members.size >= limit
                end

                total_stale += stale_members.size

                if repair && stale_members.any?
                  redis.zrem(key, stale_members)
                  total_removed += stale_members.size
                end
              end

              { keys_scanned: keys_scanned, stale: total_stale, removed: total_removed }
            end

            # GC expired or orphaned pending invitations
            def gc_pending_invitations(redis, repair, limit)
              expired = 0
              orphaned = 0
              removed = 0
              keys_scanned = 0

              redis.scan_each(match: INVITATION_PATTERN, count: SCAN_COUNT) do |key|
                keys_scanned += 1
                stale_members = []

                zscan_each(redis, key) do |member|
                  membership_key = "org_membership:#{member}"

                  unless redis.exists?(membership_key)
                    orphaned += 1
                    stale_members << member
                    next
                  end

                  # Check if the membership record is expired
                  begin
                    membership = Onetime::OrganizationMembership.load(member)
                    if membership&.expired?
                      expired += 1
                      stale_members << member
                      membership.destroy_with_index_cleanup! if repair
                    end
                  rescue StandardError => ex
                    scheduler_logger.warn "[ParticipationGCJob] Error checking membership #{member}: #{ex.message}"
                  end

                  break if stale_members.size >= limit
                end

                if repair && stale_members.any?
                  # Remove orphaned entries (expired ones already cleaned up via destroy_with_index_cleanup!)
                  orphaned_members = stale_members.select { |m| !redis.exists?("org_membership:#{m}") }
                  redis.zrem(key, orphaned_members) if orphaned_members.any?
                  removed += stale_members.size
                end
              end

              { keys_scanned: keys_scanned, expired: expired, orphaned: orphaned, removed: removed }
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
