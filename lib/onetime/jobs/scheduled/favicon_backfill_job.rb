# lib/onetime/jobs/scheduled/favicon_backfill_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'
require_relative '../publisher'
require_relative '../workers/job_lifecycle'

module Onetime
  module Jobs
    module Scheduled
      # Nightly scan that enqueues a favicon fetch for every custom domain still
      # missing an auto-fetched icon whose backoff window has elapsed (#3780).
      #
      # Auto-discovered by SchedulerCommand#load_scheduled_jobs (globs
      # scheduled/**/*_job.rb + ObjectSpace): the filename ends _job.rb and
      # .schedule is overridden, so NO manual registration is required.
      #
      # Disabled by default. Requires BOTH gates — this job's flag AND the
      # favicon_fetch worker flag — because an enqueue is pure waste when the
      # worker is off (it consumes+acks without fetching). Configuration
      # (config.yaml):
      #   jobs:
      #     favicon_fetch:
      #       enabled: true          # worker must be running to consume
      #     favicon_backfill:
      #       enabled: true
      #       cron: '0 3 * * *'
      #       batch_size: 500        # domains loaded+scanned per page
      #       max_attempts: 6        # permanent stop after N terminal misses
      #       base_days: 1           # (read by the operation's backoff curve)
      #       cap_days: 30           # (read by the operation's backoff curve)
      #
      # Backoff bookkeeping lives on CustomDomain (favicon_fetch_attempts /
      # favicon_fetch_next_at), written by Operations::FetchDomainFavicon's
      # terminal recorders. This job only READS those fields to decide eligibility.
      class FaviconBackfillJob < ScheduledJob
        JobLifecycle         = Onetime::Jobs::Workers::JobLifecycle
        DEFAULT_CRON         = '0 3 * * *'
        DEFAULT_BATCH_SIZE   = 500
        DEFAULT_MAX_ATTEMPTS = 6
        # A domain stuck at PROCESSING longer than this is treated as abandoned
        # (a DLQ'd FetchTimeout leaves status='processing' with no terminal
        # stamp) and becomes eligible again. Must exceed the worker's total
        # requeue window (with_retry + broker redelivery).
        STUCK_PROCESSING_S   = 3600

        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info "[FaviconBackfillJob] Scheduling with cron: #{cron_pattern}"

            cron(scheduler, cron_pattern) do
              backfill_favicons
            end
          end

          private

          # Both gates required: no point enqueuing if the worker drops messages.
          def enabled?
            OT.conf.dig('jobs', 'favicon_backfill', 'enabled') == true &&
              OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true
          end

          def cron_pattern
            OT.conf.dig('jobs', 'favicon_backfill', 'cron') || DEFAULT_CRON
          end

          def batch_size
            size = OT.conf.dig('jobs', 'favicon_backfill', 'batch_size').to_i
            size.positive? ? size : DEFAULT_BATCH_SIZE
          end

          def max_attempts
            n = OT.conf.dig('jobs', 'favicon_backfill', 'max_attempts').to_i
            n.positive? ? n : DEFAULT_MAX_ATTEMPTS
          end

          # Paginate the FULL CustomDomain.instances set in batch_size chunks so a
          # population larger than one batch is fully covered (a single newest
          # batch would starve older domains forever). revrangeraw(offset, offset +
          # size - 1) walks the sorted set; an empty or short page ends the scan.
          def backfill_favicons
            now      = Familia.now.to_i
            size     = batch_size
            offset   = 0
            scanned  = 0
            enqueued = 0

            loop do
              ids = Onetime::CustomDomain.instances.revrangeraw(offset, offset + size - 1)
              break if ids.empty?

              Onetime::CustomDomain.load_multi(ids).compact.each do |d|
                scanned += 1
                next unless eligible?(d, now)

                Onetime::Jobs::Publisher.enqueue_favicon_fetch(d.identifier)
                enqueued += 1
              end

              break if ids.size < size # short page => last page

              offset += size
            end

            scheduler_logger.info "[FaviconBackfillJob] Scanned #{scanned}, enqueued #{enqueued}"
          rescue StandardError => ex
            scheduler_logger.error "[FaviconBackfillJob] Unexpected error: #{ex.class} - #{ex.message}"
            scheduler_logger.error ex.backtrace.first(5).join("\n") if OT.debug?
          end

          # Eligible = has NO stored icon AND under the attempt cap AND not a
          # fresh in-flight processing AND its backoff window has elapsed.
          def eligible?(d, now)
            return false if d.favicon_fetched == true # icon already stored

            # Any domain that already has a stored icon is ineligible. The nightly
            # job enqueues a force:false fetch, and FetchDomainFavicon's
            # overwrite_guard skips over ANY existing icon (user upload, legacy
            # untagged, AND an existing auto_fetch icon) WITHOUT stamping backoff.
            # Re-enqueuing such a domain therefore churns it every night forever.
            # The subtle case this closes: a force refresh that finds nothing runs
            # record_none_found, which sets favicon_fetched=false but leaves the
            # stale auto_fetch icon in place — so favicon_fetched alone (line above)
            # does NOT catch it; the filename check does. Only the force manual
            # refresh path (which bypasses eligible?) may re-fetch over an icon.
            return false unless d.icon['filename'].to_s.empty?

            return false if d.favicon_fetch_attempts.to_i >= max_attempts # permanent stop

            # PROCESSING counts as in-flight ONLY while fresh, measured from the
            # start stamp set in mark_processing. A DLQ'd FetchTimeout leaves
            # status='processing' with no *terminal* stamp, but started_at is set,
            # so once it ages past STUCK_PROCESSING_S the abandoned run becomes
            # eligible again while a genuinely in-flight run stays protected.
            # started_at.to_i => 0 for a pre-field domain also reads as stale.
            if d.favicon_fetch_status == JobLifecycle::PROCESSING
              started = d.favicon_fetch_started_at.to_i
              fresh   = started.positive? && (now - started) < STUCK_PROCESSING_S
              return false if fresh
            end

            nxt = d.favicon_fetch_next_at.to_i
            nxt.zero? || nxt <= now # never scheduled, or backoff elapsed
          end
        end
      end
    end
  end
end
