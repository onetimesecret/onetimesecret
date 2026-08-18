.. A new scriv changelog fragment.

Added
-----

- Nightly entitlement re-materialization job. Org entitlement snapshots
  previously only converged with their plan definitions when a Stripe
  webhook happened to re-apply the subscription — weeks away for monthly
  plans, never for orgs with no billing events. The new scheduled job runs
  the idempotent batch materialization (cascading to active memberships,
  preserving per-org grants and revokes) so plan-definition drift is
  repaired within a day and reported as a structured log line. The job
  pulls the plan catalog from Stripe before materializing and aborts if
  the pull fails, so it can never bake a stale entitlement set onto orgs;
  standalone installs without a Stripe API key are skipped gracefully.
  Default off; enable with ``jobs.maintenance.enabled`` plus
  ``jobs.maintenance.entitlement_materialize.enabled`` (cron default
  ``0 3 * * *``). (#4203)

- The plan cache refresh job (``jobs.plan_cache_refresh.enabled``, on by
  default) is now documented for production use alongside the new job in
  ``docs/runbooks/entitlement-rematerialization.md``, which covers the
  config flags, the pull-before-materialize ordering guarantee, scheduler
  deployment prerequisites, post-deploy verification, and manual repair
  via the ``bin/ots billing`` and ``bin/ots org`` verbs. (#4203)

AI Assistance
-------------

- Claude implemented the scheduled job wrapping the existing
  ``Billing::Operations::MaterializePlans`` operation with an in-job
  catalog pull and fail-closed ordering (abort on pull failure, never
  materialize from a stale cache), plumbed the double-gated configuration
  through the Ruby defaults and the TypeScript schema, wrote the test
  coverage, and authored the operator runbook.
