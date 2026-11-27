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
      # (warning_hours - check_interval) before the secret expires. A sent
      # warning takes the receipt off the timeline, and the warnings_sent set
      # stops a second one if that removal fails. There is no delayed
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
      #   - expiration_timeline: Sorted set (score = expiration timestamp) of
      #     receipts still to be warned or decided
      #   - warnings_sent: Set for deduplication
      #
      # Rate Limiting:
      #   The batch_size setting prevents queue overflow when many secrets expire
      #   simultaneously. Remaining secrets are processed in subsequent runs.
      #   batch_size counts warnings sent, not timeline entries read; reads are
      #   capped separately at batch_size × SCAN_LIMIT_FACTOR (see
      #   process_expiring_secrets for why the order matters).
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

        # Timeline entries read per run, as a multiple of batch_size. Bounds
        # one run's Redis work when many entries are skipped but kept (for
        # example owners with no email yet).
        SCAN_LIMIT_FACTOR = 10

        class << self
          def schedule(scheduler)
            return unless enabled?

            interval = OT.conf.get('jobs.expiration_warnings.check_interval', '1h')

            scheduler_logger.info "[ExpirationWarningJob] Scheduling with interval: #{interval}"

            every(scheduler, interval, first_in: '30s') do
              process_expiring_secrets
            end
          end

          private

          def enabled?
            OT.conf.get('jobs.expiration_warnings.enabled') == true
          end

          def warning_hours
            hours = OT.conf.get('jobs.expiration_warnings.warning_hours').to_i
            hours > 0 ? hours : 24
          end

          def batch_size
            size = OT.conf.get('jobs.expiration_warnings.batch_size').to_i
            size > 0 ? size : DEFAULT_BATCH_SIZE
          end

          def process_expiring_secrets
            warning_window = warning_hours * 3600
            limit          = batch_size
            scan_limit     = limit * SCAN_LIMIT_FACTOR

            # ORDER MATTERS. batch_size caps the warnings sent per run, and
            # scan_limit caps the timeline entries read per run. Neither may
            # be spent on an entry the job will not mail. The job used to
            # take batch_size entries off the front of the timeline and only
            # then filter out receipts already warned. Warned receipts stayed
            # on the timeline until they expired, so batch_size of them
            # expiring sooner filled every slot: a receipt that became due
            # later was not examined, and when more than batch_size receipts
            # became due per check interval some were never warned at all.
            # Nothing reported the loss. Now the window is read page by
            # page, soonest first, and skipped entries do not count toward
            # batch_size. A sent warning, and every entry that can never be
            # mailed, leaves the timeline, so the next run does not read it
            # again. Only entries that may still be mailed later (an owner
            # with no email yet, a failed enqueue) stay; the offset steps
            # past them. If this loop ever goes back to filtering after
            # taking a fixed slice, warnings for newer secrets are dropped
            # with no error.
            processed = 0
            skipped   = 0
            scanned   = 0
            offset    = 0 # entries before this position are kept on the timeline

            while processed < limit && scanned < scan_limit
              count = [limit, scan_limit - scanned].min
              page  = Onetime::Receipt.expiring_within(warning_window, offset: offset, count: count)
              break if page.empty?

              page.each do |receipt_id|
                scanned += 1
                case examine_entry(receipt_id)
                when :sent
                  processed += 1
                when :dropped
                  skipped += 1
                when :kept
                  skipped += 1
                  offset  += 1
                when :failed
                  offset += 1
                end
                break if processed >= limit || scanned >= scan_limit
              end

              # A short page is the end of the window.
              break if page.size < count
            end

            if processed >= limit || scanned >= scan_limit
              scheduler_logger.warn "[ExpirationWarningJob] Throttling: stopped after #{processed} warnings and " \
                                    "#{scanned} entries read (batch_size #{limit}); the rest wait for the next run"
            else
              scheduler_logger.debug "[ExpirationWarningJob] Read #{scanned} entries expiring within #{warning_hours}h"
            end

            # Self-cleaning: remove entries that have already expired
            cleanup_count = Onetime::Receipt.cleanup_expired_from_timeline(Familia.now.to_f - CLEANUP_GRACE_PERIOD_SECONDS)

            # Clean up orphaned warnings_sent entries that no longer exist in expiration_timeline
            # This prevents unbounded growth of the warnings_sent set
            orphan_cleanup_count = Onetime::Receipt.cleanup_orphaned_warnings

            scheduler_logger.info "[ExpirationWarningJob] Processed: #{processed}, Skipped: #{skipped}, Cleaned: #{cleanup_count}, Orphans: #{orphan_cleanup_count}"
          end

          # Decide one timeline entry. Returns:
          #   :sent    - warning enqueued; marked warned and taken off the timeline
          #   :dropped - can never be mailed; taken off the timeline
          #   :kept    - not mailed now but may be later; left on the timeline
          #   :failed  - enqueue raised; left on the timeline for the next run
          def examine_entry(receipt_id)
            # Already warned: a receipt marked before warned receipts left
            # the timeline, or one whose removal failed. Drop the entry so it
            # never takes a slot again; warnings_sent still prevents a second
            # warning.
            return drop(receipt_id) if Onetime::Receipt.warning_sent?(receipt_id)

            # The receipt is gone (expired or deleted): nothing to warn about.
            receipt = Onetime::Receipt.load(receipt_id)
            return drop(receipt_id) unless receipt&.exists?

            # Only a secret that is still unconsumed can expire. A reveal or
            # burn takes the receipt off the timeline, but an entry written
            # before that existed (or left by a failed removal) can remain.
            # Drop it so later scans do not load it again.
            return drop(receipt) unless receipt.live?

            # Skip anonymous secrets (no owner to notify). Permanent, like
            # the two skips below, so the entry is dropped and later runs do
            # not read it again.
            return drop(receipt) if receipt.anonymous?

            # A missing email is kept, since the owner can still add one. So
            # is a blank one (empty or whitespace only) on a verified account.
            # A blank email on an anonymous or unverified account falls
            # through to the notifiable? check below and is dropped.
            owner = receipt.load_owner
            return :kept if owner.nil? || owner.email.nil?
            return :kept if owner.email.to_s.strip.empty? && owner.account_verified?

            # Who may get owner mail at all: see Customer#notifiable?. The
            # entry is dropped so later runs do not read it again for an
            # owner who never verifies. Unlike anonymity this can change: an
            # owner who verifies after the scan gets no warning for an entry
            # already dropped.
            return drop(receipt) unless owner.notifiable?

            # Skip when the secret is already gone, or is account mechanics
            # (Secret#account_mechanics?: a verification, password-reset or
            # email-change link; the same rule as the reveal notice).
            # Verification links created before spawn_pair could leave them
            # off the timeline are still on it; their owner is not warned.
            secret = receipt.load_secret
            return drop(receipt) if secret.nil? || secret.account_mechanics?

            return :failed unless enqueue_warning_email(receipt, owner)

            # Mark first, then leave the timeline: if the removal fails, the
            # mark still stops a second warning and the next scan drops the
            # entry.
            Onetime::Receipt.mark_warning_sent(receipt_id)
            receipt.unregister_from_expiration_notifications
            :sent
          end

          # Take an entry off the timeline. :dropped when it is off; :kept when
          # the removal failed, so the caller's offset steps past an entry
          # still in place instead of reading it again in this run.
          #
          # @param receipt_or_id [Onetime::Receipt, String]
          # @return [Symbol] :dropped or :kept
          def drop(receipt_or_id)
            removed = if receipt_or_id.is_a?(String)
                        Onetime::Receipt.remove_from_expiration_timeline(receipt_or_id)
                        true
                      else
                        receipt_or_id.unregister_from_expiration_notifications
                      end
            removed == false ? :kept : :dropped
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
            # Sender: the receipt's stored domain_id, while it still names
            # the same domain for the same organization
            # (Receipt.sender_domain_id_for), so a secret shared from a
            # custom domain is announced from that domain's sender and never
            # from a later holder of the name. share_domain itself stays out
            # of the payload: it would move the layout's header and footer
            # links to the custom domain (brand_baseuri), while this account
            # notice links the owner to the canonical host
            # (ExpirationWarning#recent_uri).
            domain_id = receipt.sender_domain_id
            # Blank ("") locales are truthy and slip past a bare `||`.
            locale    = owner.locale.to_s.strip.empty? ? OT.default_locale : owner.locale

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
                locale: locale,
              },
              domain_id: domain_id,
            )

            scheduler_logger.debug "[ExpirationWarningJob] Enqueued warning for #{receipt.shortid} " \
                                   "(expires: #{receipt.secret_expiration})"
            true
          rescue StandardError => ex
            scheduler_logger.error "[ExpirationWarningJob] Failed to enqueue warning for #{receipt.shortid}: #{ex.message}"
            false
          end
        end
      end
    end
  end
end
