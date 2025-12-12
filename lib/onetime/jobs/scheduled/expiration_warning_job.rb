# lib/onetime/jobs/scheduled/expiration_warning_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'

module Onetime
  module Jobs
    module Scheduled
      # Scheduled job to send expiration warning emails
      #
      # Scans for secrets that will expire within the configured warning window
      # and schedules warning emails to their owners. Uses Redis sorted sets for
      # efficient time-range queries and a set for deduplication.
      #
      # Configuration (config.yaml):
      #   jobs:
      #     expiration_warnings:
      #       enabled: true
      #       check_interval: '1h'   # How often to scan
      #       warning_hours: 24      # Warn N hours before expiry
      #       min_ttl_hours: 48      # Only warn for secrets with TTL > this
      #
      # Data structures (in Metadata):
      #   - expiration_timeline: Sorted set (score = expiration timestamp)
      #   - warnings_sent: Set for deduplication
      #
      class ExpirationWarningJob < ScheduledJob
        # Send warning email 1 hour before secret expiration
        WARNING_BUFFER_SECONDS = 3600

        # Grace period for cleanup: remove timeline entries that expired over 1 hour ago
        CLEANUP_GRACE_PERIOD_SECONDS = 3600

        class << self
          def schedule(scheduler)
            return unless enabled?

            interval = OT.conf.dig('jobs', 'expiration_warnings', 'check_interval') || '1h'

            scheduler_logger.info "[ExpirationWarningJob] Scheduling with interval: #{interval}"

            every(scheduler, interval, first_in: '30s') do
              process_expiring_secrets
            end
          end

          private

          def enabled?
            OT.conf.dig('jobs', 'expiration_warnings', 'enabled') == true
          end

          def warning_hours
            hours = OT.conf.dig('jobs', 'expiration_warnings', 'warning_hours').to_i
            hours > 0 ? hours : 24
          end

          def process_expiring_secrets
            warning_window = warning_hours * 3600
            expiring_ids = Onetime::Metadata.expiring_within(warning_window)

            scheduler_logger.debug "[ExpirationWarningJob] Found #{expiring_ids.size} secrets expiring within #{warning_hours}h"

            processed = 0
            skipped = 0

            expiring_ids.each do |metadata_id|
              # Skip if warning already sent
              if Onetime::Metadata.warning_sent?(metadata_id)
                skipped += 1
                next
              end

              metadata = Onetime::Metadata.load(metadata_id)
              next unless metadata&.exists?

              # Skip anonymous secrets (no owner to notify)
              if metadata.anonymous?
                skipped += 1
                next
              end

              owner = metadata.load_owner
              unless owner&.email
                skipped += 1
                next
              end

              schedule_warning_email(metadata, owner)
              Onetime::Metadata.mark_warning_sent(metadata_id)
              processed += 1
            end

            # Self-cleaning: remove entries that have already expired
            cleanup_count = Onetime::Metadata.cleanup_expired_from_timeline(Familia.now.to_f - CLEANUP_GRACE_PERIOD_SECONDS)

            scheduler_logger.info "[ExpirationWarningJob] Processed: #{processed}, Skipped: #{skipped}, Cleaned: #{cleanup_count}"
          end

          def schedule_warning_email(metadata, owner)
            # Calculate delay: send warning before actual expiration
            # (or immediately if less than the buffer time remains)
            seconds_until_expiry = metadata.secret_expiration.to_i - Familia.now.to_i
            delay = [seconds_until_expiry - WARNING_BUFFER_SECONDS, 0].max

            Onetime::Jobs::Publisher.schedule_email(
              :expiration_warning,
              {
                recipient: owner.email,
                secret_key: metadata.secret_shortid,
                expires_at: metadata.secret_expiration,
                share_domain: metadata.share_domain,
              },
              delay_seconds: delay,
            )

            scheduler_logger.debug "[ExpirationWarningJob] Scheduled warning for #{metadata.identifier} " \
                                   "(delay: #{delay}s, expires: #{metadata.secret_expiration})"
          rescue StandardError => ex
            scheduler_logger.error "[ExpirationWarningJob] Failed to schedule warning for #{metadata.identifier}: #{ex.message}"
          end
        end
      end
    end
  end
end
