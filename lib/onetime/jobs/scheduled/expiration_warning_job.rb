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
      # and enqueues a warning email to each owner. Uses Redis sorted sets for
      # efficient time-range queries and a set for deduplication.
      #
      # Configuration (config.yaml):
      #   jobs:
      #     expiration_warnings:
      #       enabled: true
      #       check_interval: '1h'   # How often to scan
      #       warning_hours: 24      # Warn once a secret is within N hours of expiry
      #       min_ttl_hours: 48      # Only warn for secrets with TTL > this
      #       batch_size: 100        # Max warnings per run (rate limiting)
      #
      # Timing: the email is enqueued on the first scan that finds the secret
      # inside the warning window, so it goes out between warning_hours and
      # (warning_hours - check_interval) before the secret expires, and the
      # warnings_sent set keeps it to one per receipt. There is no delayed
      # delivery. The job used to publish to email.message.schedule with a
      # per-message TTL so the mail would leave one hour before expiry, but
      # nothing consumed that queue: with jobs enabled the message expired
      # into dlq.email.message and DlqEmailConsumerJob discarded it, so no
      # warning was ever sent, while with jobs disabled the publisher's
      # fallback ignored the delay and sent at scan time. Scan time is now the
      # one behavior on both paths (#4844). To warn closer to expiry, lower
      # warning_hours.
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

              if enqueue_warning_email(receipt, owner)
                Onetime::Receipt.mark_warning_sent(receipt_id)
                processed += 1
              end
            end

            # Self-cleaning: remove entries that have already expired
            cleanup_count = Onetime::Receipt.cleanup_expired_from_timeline(Familia.now.to_f - CLEANUP_GRACE_PERIOD_SECONDS)

            # Clean up orphaned warnings_sent entries that no longer exist in expiration_timeline
            # This prevents unbounded growth of the warnings_sent set
            orphan_cleanup_count = Onetime::Receipt.cleanup_orphaned_warnings

            scheduler_logger.info "[ExpirationWarningJob] Processed: #{processed}, Skipped: #{skipped}, Cleaned: #{cleanup_count}, Orphans: #{orphan_cleanup_count}"
          end

          # Enqueue the warning email for immediate delivery.
          #
          # Publisher.enqueue_email returns true when the message reached
          # email.message.send and false when the publisher's fallback
          # delivered it instead (jobs disabled, broker unreachable). Both mean
          # the mail is on its way, so the return value is not consulted. Only
          # an exception leaves the receipt unmarked, to be retried on the
          # next scan.
          #
          # @return [Boolean] true if the email was enqueued, false on failure
          def enqueue_warning_email(receipt, owner)
            Onetime::Jobs::Publisher.enqueue_email(
              :expiration_warning,
              {
                recipient: owner.email,
                # An account notification, like secret_revealed: the short id
                # names the secret, and the template links to the owner's
                # recent-secrets page on the canonical host. No receipt or
                # secret identifier goes by email: both are bearer
                # capabilities (the receipt route answers without an
                # ownership check and returns the share link).
                secret_shortid: receipt.secret_shortid,
                expires_at: receipt.secret_expiration,
              },
            )

            scheduler_logger.debug "[ExpirationWarningJob] Enqueued warning for #{receipt.identifier} " \
                                   "(expires: #{receipt.secret_expiration})"
            true
          rescue StandardError => ex
            scheduler_logger.error "[ExpirationWarningJob] Failed to enqueue warning for #{receipt.identifier}: #{ex.message}"
            false
          end
        end
      end
    end
  end
end
