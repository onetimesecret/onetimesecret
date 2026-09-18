# lib/onetime/jobs/scheduled/domain_refresh_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'

module Onetime
  module Jobs
    module Scheduled
      # Scheduled job that refreshes cached vhost/resolving status for
      # custom domains so the domains-list page shows current state without
      # depending on a user visiting the verify page. See issue #3080.
      #
      # Disabled by default. Configuration (config.yaml):
      #   jobs:
      #     domain_refresh:
      #       enabled: true
      #       check_interval: '30m'
      #       batch_size: 200    # max domains processed per run (clock-derived page walks the full set)
      #       rate_limit: 0.5    # seconds between Approximated API calls
      #
      # The Approximated rate limit (0.5s) caps a 200-domain run at ~100s.
      class DomainRefreshJob < ScheduledJob
        DEFAULT_BATCH_SIZE = 200
        DEFAULT_RATE_LIMIT = 0.5
        DEFAULT_INTERVAL   = '30m'

        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info "[DomainRefreshJob] Scheduling with interval: #{interval}"

            every(scheduler, interval, first_in: '2m') do
              refresh_domains
            end
          end

          private

          def enabled?
            OT.conf.dig('jobs', 'domain_refresh', 'enabled') == true
          end

          def interval
            OT.conf.dig('jobs', 'domain_refresh', 'check_interval') || DEFAULT_INTERVAL
          end

          def batch_size
            size = OT.conf.dig('jobs', 'domain_refresh', 'batch_size').to_i
            size.positive? ? size : DEFAULT_BATCH_SIZE
          end

          def rate_limit
            limit = OT.conf.dig('jobs', 'domain_refresh', 'rate_limit')
            limit.is_a?(Numeric) && limit >= 0 ? limit.to_f : DEFAULT_RATE_LIMIT
          end

          # Walk the FULL CustomDomain.instances set one page per run. Always
          # taking the newest batch starved every domain past the first
          # batch_size forever: their cached vhost/resolving state never
          # refreshed. One page per run (not the whole set) keeps a run bounded
          # by the Approximated rate limit.
          def refresh_domains
            offset      = page_offset(Onetime::CustomDomain.instances.element_count, Familia.now.to_i)
            identifiers = Onetime::CustomDomain.instances.revrangeraw(offset, offset + batch_size - 1)

            # load_multi pipelines the batch fetch; .all would HGETALL every domain.
            domains = Onetime::CustomDomain.load_multi(identifiers).compact
            if domains.empty?
              scheduler_logger.debug '[DomainRefreshJob] No domains to refresh'
              return
            end

            scheduler_logger.info "[DomainRefreshJob] Refreshing #{domains.size} domain(s) from offset #{offset}"

            result = Onetime::Operations::VerifyDomain.new(
              domains: domains,
              rate_limit: rate_limit,
              persist: true,
            ).call

            scheduler_logger.info "[DomainRefreshJob] Done in #{result.duration_seconds}s — " \
                                  "verified=#{result.verified_count} failed=#{result.failed_count} " \
                                  "indeterminate=#{result.indeterminate_count} demoted=#{result.demoted_count}"
          rescue StandardError => ex
            scheduler_logger.error "[DomainRefreshJob] Unexpected error: #{ex.class} - #{ex.message}"
            scheduler_logger.error ex.backtrace.first(5).join("\n") if OT.debug?
          end

          # The page is derived from the clock, so there is no position to
          # persist, expire, or reset: tick counts whole intervals since the
          # epoch and wraps over the page count. The modulus is pages, not
          # domains, so windows stay aligned to batch_size (the last page is
          # simply short) and the walk only re-phases when the set grows or
          # shrinks across a page boundary, not on every add or remove. A
          # re-phase, or a tick the scheduler skipped or fired twice, costs a
          # page one extra cycle or one repeat refresh.
          def page_offset(total, now)
            pages = (total.to_f / batch_size).ceil
            return 0 if pages.zero?

            tick = now / interval_seconds(interval)
            (tick % pages) * batch_size
          end
        end
      end
    end
  end
end
