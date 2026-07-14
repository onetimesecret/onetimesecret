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

          # Eligible = lacks an auto_fetch favicon AND under the attempt cap AND
          # not a fresh in-flight processing AND its backoff window has elapsed.
          def eligible?(d, now)
            return false if d.favicon_fetched == true # icon already stored

            src = d.icon['favicon_source'].to_s
            return false if !src.empty? && src != 'auto_fetch' # user_upload/legacy — guard would skip anyway
            return false if d.favicon_fetch_attempts.to_i >= max_attempts # permanent stop

            # PROCESSING counts as in-flight ONLY while fresh. A DLQ'd FetchTimeout
            # leaves status='processing' with no completed_at (to_i => 0), so
            # now - 0 exceeds the threshold and the abandoned job is re-enqueued.
            # The rare cost is a duplicate enqueue for a domain actively fetching
            # at scan time; the operation's overwrite guard makes that a no-op.
            if d.favicon_fetch_status == JobLifecycle::PROCESSING
              fresh = (now - d.favicon_fetch_completed_at.to_i) < STUCK_PROCESSING_S
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
