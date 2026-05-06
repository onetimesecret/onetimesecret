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
      #       batch_size: 200    # max domains processed per run
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

          def refresh_domains
            # Pull only the IDs we'll actually process; .all would HGETALL every
            # domain before slicing. load_multi pipelines the batch fetch.
            identifiers = Onetime::CustomDomain.instances.revrangeraw(0, batch_size - 1)
            domains     = Onetime::CustomDomain.load_multi(identifiers).compact
            if domains.empty?
              scheduler_logger.debug '[DomainRefreshJob] No domains to refresh'
              return
            end

            scheduler_logger.info "[DomainRefreshJob] Refreshing #{domains.size} domain(s)"

            result = Onetime::Operations::VerifyDomain.new(
              domains: domains,
              rate_limit: rate_limit,
              persist: true,
            ).call

            scheduler_logger.info "[DomainRefreshJob] Done in #{result.duration_seconds}s — " \
                                  "verified=#{result.verified_count} failed=#{result.failed_count}"
          rescue StandardError => ex
            scheduler_logger.error "[DomainRefreshJob] Unexpected error: #{ex.class} - #{ex.message}"
            scheduler_logger.error ex.backtrace.first(5).join("\n") if OT.debug?
          end
        end
      end
    end
  end
end
