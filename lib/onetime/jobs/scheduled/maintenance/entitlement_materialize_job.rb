# lib/onetime/jobs/scheduled/maintenance/entitlement_materialize_job.rb
#
# frozen_string_literal: true

require_relative '../../maintenance_job'

module Onetime
  module Jobs
    module Scheduled
      module Maintenance
        # Nightly entitlement re-materialization (issue #4203).
        #
        # Org entitlements are materialized from the Redis plan cache, and
        # without this job nothing converges them on a schedule: after a plan
        # definition changes, an org's materialized snapshot only self-heals
        # when its next Stripe webhook re-runs ApplySubscriptionToOrg — weeks
        # away for monthly subscriptions, never for orgs with no billing
        # events. This job runs the idempotent batch operation
        # Billing::Operations::MaterializePlans (cascading to active
        # memberships) so drift is repaired within a day.
        #
        # Ordering constraint: the job refreshes the plan cache
        # (Billing::Operations::Catalog::Pull) before materializing, and
        # aborts unless that pull reports a verified catalog. Materializing
        # from a stale cache bakes the wrong entitlement set fleet-wide —
        # that is the incident this job exists to prevent, so the failure
        # mode is fail-closed: no verified pull, no materialize. Note that a
        # pull can succeed without verifying anything (an empty Stripe
        # catalog is a successful no-op that leaves the old cache in place),
        # which is why the gate is Pull::Result#catalog_verified rather
        # than #success.
        #
        # Standalone installs (no Stripe API key) skip gracefully, like
        # PlanCacheRefreshJob.
        #
        # The run's counts (succeeded/failed/cascade totals) are logged as a
        # single structured JSON line at INFO via MaintenanceJob.with_stats so
        # drift becomes observable, not just repaired. Per-org failures are
        # additionally logged at ERROR — never swallowed.
        #
        # Configuration (config.yaml):
        #   jobs:
        #     maintenance:
        #       enabled: true
        #       entitlement_materialize:
        #         enabled: true
        #         cron: '0 3 * * *'
        #
        # Default disabled; requires BOTH jobs.maintenance.enabled and this
        # job's own flag. The 03:00 default runs while PlanCacheRefreshJob's
        # 6h interval keeps the cache warm, but the in-job pull means this job
        # does not depend on that job being enabled or ordered before it.
        #
        class EntitlementMaterializeJob < MaintenanceJob
          JOB_KEY = 'entitlement_materialize'

          # Cap the per-org error detail included in logs so a fleet-wide
          # failure doesn't produce an unbounded log line.
          MAX_LOGGED_ERRORS = 20

          class << self
            def schedule(scheduler)
              return unless job_enabled?(JOB_KEY)

              cron_pattern = job_cron(JOB_KEY)
              scheduler_logger.info "[EntitlementMaterializeJob] Scheduling with cron: #{cron_pattern}"

              cron(scheduler, cron_pattern) do
                with_stats('EntitlementMaterializeJob') do |report|
                  run_materialization(report)
                end
              end
            end

            private

            def run_materialization(report)
              # Skip if no Stripe API key configured (standalone mode).
              # Standalone orgs are handled by materialize_standalone_entitlements
              # on the read path; there is no plan catalog to converge against.
              stripe_key = Onetime.billing_config.stripe_key
              if stripe_key.to_s.strip.empty?
                report[:skipped] = 'no_stripe_key'
                scheduler_logger.debug '[EntitlementMaterializeJob] Skipping: No Stripe API key configured'
                return
              end

              return unless refresh_plan_cache(report)

              materialize_plans(report)
            end

            # Refresh the Redis plan cache from Stripe. Returns true only when
            # the cache is confirmed fresh; any failure aborts the run so we
            # never materialize from a potentially stale cache.
            def refresh_plan_cache(report)
              pull = Billing::Operations::Catalog::Pull.call

              unless pull.success
                report[:aborted]     = 'catalog_pull_failed'
                report[:pull_errors] = Array(pull.errors).first(MAX_LOGGED_ERRORS)
                scheduler_logger.error(
                  '[EntitlementMaterializeJob] Aborting: catalog pull failed, ' \
                  "refusing to materialize from a stale cache: #{Array(pull.errors).first}",
                )
                return false
              end

              # `success` is not a freshness guarantee. A Stripe catalog that
              # returns no matching products is a successful no-op: Pull
              # returns early, the prune/rebuild/timestamp path never runs,
              # and the previously cached plans stay in Redis. Materializing
              # there is exactly the stale-cache failure this job prevents,
              # so gate on the catalog_verified signal instead.
              unless pull.catalog_verified
                report[:aborted]      = 'catalog_pull_unverified'
                report[:plans_synced] = pull.plans_synced
                scheduler_logger.error(
                  '[EntitlementMaterializeJob] Aborting: catalog pull succeeded but verified no plans ' \
                  "(plans_synced=#{pull.plans_synced}), refusing to materialize from a stale cache",
                )
                return false
              end

              report[:plans_synced] = pull.plans_synced
              true
            rescue StandardError => ex
              report[:aborted]     = 'catalog_pull_raised'
              report[:pull_errors] = ["#{ex.class}: #{ex.message}"]
              scheduler_logger.error(
                '[EntitlementMaterializeJob] Aborting: catalog pull raised, ' \
                "refusing to materialize from a stale cache: #{ex.class} - #{ex.message}",
              )
              false
            end

            def materialize_plans(report)
              result = Billing::Operations::MaterializePlans.call(include_memberships: true)

              report[:scanned]               = result.scanned
              report[:succeeded]             = result.succeeded
              report[:failed]                = result.failed
              report[:skipped_no_plan]       = result.skipped_no_plan
              report[:orgs_cascaded]         = result.orgs_cascaded
              report[:memberships_succeeded] = result.memberships_succeeded
              report[:memberships_failed]    = result.memberships_failed

              return unless result.failed.positive?

              report[:errors] = result.errors.first(MAX_LOGGED_ERRORS)
              scheduler_logger.error(
                "[EntitlementMaterializeJob] #{result.failed} org(s) failed to materialize " \
                "(#{result.memberships_failed} membership cascade failures): " \
                "#{JSON.generate(result.errors.first(MAX_LOGGED_ERRORS))}",
              )
            end
          end
        end
      end
    end
  end
end
