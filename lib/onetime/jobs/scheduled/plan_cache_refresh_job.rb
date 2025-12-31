# lib/onetime/jobs/scheduled/plan_cache_refresh_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'

module Onetime
  module Jobs
    module Scheduled
      # Scheduled job to refresh Billing::Plan cache from Stripe API
      #
      # The Plan cache stores Stripe product/price data in Redis with a 12-hour TTL.
      # This job proactively refreshes the cache every 6 hours to ensure plan data
      # remains available even if Stripe webhooks fail to deliver.
      #
      # Without this safeguard, cache expiry could cause Plan.load(planid) to return
      # nil, triggering fail-closed behavior (empty entitlements for users).
      #
      # Disabled by default. Enable via config:
      #   jobs:
      #     plan_cache_refresh_enabled: true
      #
      # Configuration:
      #   - Runs every 6 hours (half of the 12-hour TTL)
      #   - First run 1 minute after scheduler starts
      #   - Skips gracefully if no Stripe API key configured (standalone mode)
      #   - Logs success with plan count or failure with error details
      #
      class PlanCacheRefreshJob < ScheduledJob
        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info '[PlanCacheRefreshJob] Scheduling with interval: 6h'

            every(scheduler, '6h', first_in: '1m') do
              refresh_plan_cache
            end
          end

          private

          def enabled?
            OT.conf.dig('jobs', 'plan_cache_refresh_enabled') == true
          end

          def refresh_plan_cache
            # Skip if no Stripe API key configured (standalone mode)
            stripe_key = Onetime.billing_config.stripe_key
            if stripe_key.to_s.strip.empty?
              scheduler_logger.debug '[PlanCacheRefreshJob] Skipping: No Stripe API key configured'
              return
            end

            scheduler_logger.info '[PlanCacheRefreshJob] Starting plan cache refresh from Stripe'

            start_time  = Time.now
            plans_count = Billing::Plan.refresh_from_stripe

            duration_ms = ((Time.now - start_time) * 1000).round
            scheduler_logger.info "[PlanCacheRefreshJob] Completed: #{plans_count} plans cached in #{duration_ms}ms"
          rescue Stripe::AuthenticationError => ex
            scheduler_logger.error "[PlanCacheRefreshJob] Stripe authentication failed: #{ex.message}"
          rescue Stripe::RateLimitError => ex
            scheduler_logger.warn "[PlanCacheRefreshJob] Stripe rate limit hit, will retry next interval: #{ex.message}"
          rescue Stripe::APIConnectionError => ex
            scheduler_logger.error "[PlanCacheRefreshJob] Stripe API connection error: #{ex.message}"
          rescue Stripe::StripeError => ex
            scheduler_logger.error "[PlanCacheRefreshJob] Stripe API error: #{ex.message}"
          rescue StandardError => ex
            scheduler_logger.error "[PlanCacheRefreshJob] Unexpected error: #{ex.class} - #{ex.message}"
            scheduler_logger.error ex.backtrace.first(5).join("\n") if OT.debug?
          end
        end
      end
    end
  end
end
