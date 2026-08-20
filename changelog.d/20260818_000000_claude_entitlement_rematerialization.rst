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
  pulls the plan catalog from Stripe before materializing and aborts
  unless that pull reports a verified catalog, so it can never bake a
  stale entitlement set onto orgs; standalone installs without a Stripe
  API key are skipped gracefully. Default off; enable with
  ``jobs.maintenance.enabled`` plus
  ``jobs.maintenance.entitlement_materialize.enabled`` (cron default
  ``0 3 * * *``). (#4203)

- The catalog pull result now carries a ``catalog_verified`` signal that
  distinguishes a verified catalog from a successful no-op. A pull that
  reaches Stripe but matches no products — wrong region filter,
  unpublished products, no active recurring prices — returns before
  pruning, rebuilding the price-id cache, and stamping the sync
  timestamp, leaving the previously cached plans in place; it reports
  success but not verification. Callers that must not act on a stale
  cache can now refuse to act on one: the nightly re-materialization job
  aborts with ``catalog_pull_unverified`` instead of materializing every
  org from plans it never confirmed. Existing callers keyed on
  ``success`` are unchanged. (#4203)

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
  catalog pull and fail-closed ordering (abort unless the pull verifies
  the catalog, never materialize from a stale cache), plumbed the
  double-gated configuration through the Ruby defaults and the TypeScript
  schema, wrote the test coverage, and authored the operator runbook.
  Code review found that the original gate keyed on the pull's ``success``
  flag, which an empty Stripe catalog satisfies without refreshing
  anything; Claude then added the ``catalog_verified`` signal, moved the
  job's gate onto it, and extended the tests and runbook to cover the
  ``catalog_pull_unverified`` abort.
