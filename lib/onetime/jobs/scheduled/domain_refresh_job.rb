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
      #       batch_size: 200                # max domains processed per run (clock-derived page walks the full set)
      #       rate_limit: 0.5                # seconds between domains; unset = the strategy's own pacing
      #       dns_propagation_window: '24h'  # re-check unverified/unresolving domains every cycle for this long after creation ('0' disables)
      #
      # Pacing comes from the validation strategy (BaseStrategy#bulk_rate_limit):
      # Approximated declares 0.5s for its API rate cap, which puts a healthy
      # 200-domain run at ~100s; strategies that make our own lookups declare
      # none. A configured rate_limit overrides the strategy either way.
      #
      # Under caddy_on_demand each domain costs our own lookups instead of an
      # API call: the TXT check (TxtResolver, <= 5s) and the status probe
      # (TlsProbe: address lookup <= 3s, connect + handshake <= 5s). A healthy
      # domain takes tens of milliseconds. Every budget is only spent on a
      # timeout, so the ceiling is 13s per domain: ~43 min for a 200-domain
      # page if every stage of every domain timed out. A resolver outage is
      # the realistic bad case, and it never reaches the TLS stage: 8s per
      # domain, ~27 min per page, inside the default 30m interval.
      # Lower batch_size if pages routinely run past check_interval.
      #
      # Runs never overlap within a scheduler process (overlap: false): a
      # tick that fires while the previous run is still working is skipped,
      # not queued. Two runs at once would double the outbound lookups and
      # let both write the same domain. The skipped tick's page waits one
      # extra walk, the same cost as any other missed tick (see page_offset).
      # The guard is per process; run one scheduler process per deployment.
      class DomainRefreshJob < ScheduledJob
        DEFAULT_BATCH_SIZE             = 200
        DEFAULT_INTERVAL               = '30m'
        DEFAULT_DNS_PROPAGATION_WINDOW = '24h'

        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info "[DomainRefreshJob] Scheduling with interval: #{interval}"

            every(scheduler, interval, first_in: '2m', overlap: false) do
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

          # nil (unset or unusable) leaves pacing to the validation strategy.
          def rate_limit
            limit = OT.conf.dig('jobs', 'domain_refresh', 'rate_limit')
            limit.to_f if limit.is_a?(Numeric) && limit >= 0
          end

          def dns_propagation_window_seconds
            raw = OT.conf.dig('jobs', 'domain_refresh', 'dns_propagation_window')
            raw = DEFAULT_DNS_PROPAGATION_WINDOW if raw.nil?
            interval_seconds(raw)
          rescue ArgumentError
            interval_seconds(DEFAULT_DNS_PROPAGATION_WINDOW)
          end

          # Walk the FULL CustomDomain.instances set one page per run. Always
          # taking the newest batch starved every domain past the first
          # batch_size forever: their cached vhost/resolving state never
          # refreshed. One page per run (not the whole set) keeps a run bounded
          # by the Approximated rate limit.
          def refresh_domains
            now         = Familia.now.to_i
            offset      = page_offset(Onetime::CustomDomain.instances.element_count, now)
            identifiers = Onetime::CustomDomain.instances.revrangeraw(offset, offset + batch_size - 1)

            # load_multi pipelines the batch fetch; .all would HGETALL every domain.
            page_domains = Onetime::CustomDomain.load_multi(identifiers).compact
            warmup       = warmup_domains(now, page_domains)

            domains = page_domains + warmup
            if domains.empty?
              scheduler_logger.debug '[DomainRefreshJob] No domains to refresh'
              return
            end

            scheduler_logger.info "[DomainRefreshJob] Refreshing #{domains.size} domain(s) " \
                                  "(page=#{page_domains.size} from offset #{offset}, warmup=#{warmup.size})"

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

          # Domains created within dns_propagation_window that are still not
          # fully verified (verified=false OR resolving=false) get re-checked
          # every cycle regardless of where the page walk sits. This shortens
          # the "just added, DNS still propagating" feedback loop from up to
          # one full walk to one check_interval. Domains already picked up by
          # the page walk are excluded so VerifyDomain never sees duplicates.
          def warmup_domains(now, page_domains)
            window = dns_propagation_window_seconds
            return [] if window <= 0

            identifiers = Onetime::CustomDomain.instances.rangebyscoreraw(now - window, now)
            return [] if identifiers.empty?

            already = page_domains.to_h { |d| [d.identifier, true] }
            identifiers.reject! { |id| already[id] }
            return [] if identifiers.empty?

            Onetime::CustomDomain.load_multi(identifiers)
              .compact
              .reject { |d| d.verified && d.resolving }
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
