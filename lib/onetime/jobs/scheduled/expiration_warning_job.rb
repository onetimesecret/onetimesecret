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
      #       batch_size: 100        # Max warnings per run (rate limiting)
      #
      # Data structures (in Receipt):
      #   - expiration_timeline: Sorted set (score = expiration timestamp)
      #   - warnings_sent: Set for deduplication
      #
      # Rate Limiting:
      #   The batch_size setting prevents queue overflow when many secrets expire
      #   simultaneously. Remaining secrets are processed in subsequent runs.
      #   This is an application-level rate limit; RabbitMQ queue-level limits
      #   (x-max-length with x-overflow: reject-publish) require publisher confirms
      #   to provide feedback, which adds complexity. The batch approach is simpler
      #   and self-healing: capacity = batch_size × runs_per_day.
      #
      class ExpirationWarningJob < ScheduledJob
        # Send warning email 1 hour before secret expiration
        WARNING_BUFFER_SECONDS = 3600

        # Grace period for cleanup: remove timeline entries that expired over 1 hour ago
        CLEANUP_GRACE_PERIOD_SECONDS = 3600

        # Default batch size if not configured
        DEFAULT_BATCH_SIZE = 100

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

          def batch_size
            size = OT.conf.dig('jobs', 'expiration_warnings', 'batch_size').to_i
            size > 0 ? size : DEFAULT_BATCH_SIZE
          end

          def process_expiring_secrets
            warning_window   = warning_hours * 3600
            all_expiring_ids = Onetime::Receipt.expiring_within(warning_window)
            total_found      = all_expiring_ids.size

            # Apply batch limit to prevent queue overflow
            expiring_ids = all_expiring_ids.take(batch_size)

            if total_found > batch_size
              scheduler_logger.warn "[ExpirationWarningJob] Throttling: #{total_found} secrets expiring, " \
                                    "processing #{batch_size} (remaining will be processed in next run)"
            else
              scheduler_logger.debug "[ExpirationWarningJob] Found #{total_found} secrets expiring within #{warning_hours}h"
            end

            processed = 0
            skipped   = 0

            expiring_ids.each do |receipt_id|
              # Skip if warning already sent
              if Onetime::Receipt.warning_sent?(receipt_id)
                skipped += 1
                next
              end

              receipt = Onetime::Receipt.load(receipt_id)
              next unless receipt&.exists?

              # Skip anonymous secrets (no owner to notify)
              if receipt.anonymous?
                skipped += 1
                next
              end

              owner = receipt.load_owner
              unless owner&.email
                skipped += 1
                next
              end

              if schedule_warning_email(receipt, owner)
                Onetime::Receipt.mark_warning_sent(receipt_id)
                processed += 1
              end
            end

            # Self-cleaning: remove entries that have already expired
            cleanup_count = Onetime::Receipt.cleanup_expired_from_timeline(Familia.now.to_f - CLEANUP_GRACE_PERIOD_SECONDS)

            scheduler_logger.info "[ExpirationWarningJob] Processed: #{processed}, Skipped: #{skipped}, Cleaned: #{cleanup_count}"
          end

          # Schedule warning email for a secret
          # @return [Boolean] true if successfully scheduled, false on failure
          def schedule_warning_email(receipt, owner)
            # Calculate delay: send warning before actual expiration
            # (or immediately if less than the buffer time remains)
            seconds_until_expiry = receipt.secret_expiration.to_i - Familia.now.to_i
            delay                = [seconds_until_expiry - WARNING_BUFFER_SECONDS, 0].max

            Onetime::Jobs::Publisher.schedule_email(
              :expiration_warning,
              {
                recipient: owner.email,
                secret_key: receipt.secret_shortid,
                expires_at: receipt.secret_expiration,
                share_domain: receipt.share_domain,
              },
              delay_seconds: delay,
            )

            scheduler_logger.debug "[ExpirationWarningJob] Scheduled warning for #{receipt.identifier} " \
                                   "(delay: #{delay}s, expires: #{receipt.secret_expiration})"
            true
          rescue StandardError => ex
            scheduler_logger.error "[ExpirationWarningJob] Failed to schedule warning for #{receipt.identifier}: #{ex.message}"
            false
          end
        end
      end
    end
  end
end
