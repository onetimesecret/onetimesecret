# Entitlement re-materialization: scheduled jobs & operation

**Symptom.** An org's materialized entitlement snapshot no longer matches its
plan definition — a plan changed in Stripe, or a bad materialization baked the
wrong entitlement set — and nothing converges it until the org's next Stripe
webhook re-runs `ApplySubscriptionToOrg`. For monthly subscriptions that is
weeks away; for orgs with no billing events, never. This webhook-only
convergence is how a batch materialization against a stale plan cache once
baked a truncated entitlement set onto orgs and went unnoticed for ~3 weeks.

Two scheduled jobs close the gap (#4203):

| Job | What it does | Schedule |
| --- | ------------ | -------- |
| `EntitlementMaterializeJob` (`lib/onetime/jobs/scheduled/maintenance/entitlement_materialize_job.rb`) | Pulls the plan catalog from Stripe, then runs `Billing::Operations::MaterializePlans.call(include_memberships: true)` across all orgs, cascading to active memberships. Idempotent; preserves entitlement grants/revokes. | cron, default `0 3 * * *` |
| `PlanCacheRefreshJob` (`lib/onetime/jobs/scheduled/plan_cache_refresh_job.rb`) | Runs `Billing::Operations::Catalog::Pull` to refresh the Redis plan cache (12h TTL) so `Plan.load` never goes empty when webhooks fail. | every 6h, first run 1m after scheduler boot |

## Config flags (gate everything)

**EntitlementMaterializeJob** is default **off** and double-gated: it needs
both the maintenance master toggle AND its own flag (`etc/config.yaml`):

```yaml
jobs:
  maintenance:
    enabled: true                  # master toggle for all maintenance jobs
    entitlement_materialize:
      enabled: true                # this job's own flag
      cron: '0 3 * * *'            # default; UTC server time
```

**PlanCacheRefreshJob** is default **on**
(`etc/defaults/config.defaults.yaml`):

```yaml
jobs:
  plan_cache_refresh:
    enabled: true
```

These per-job flags are config-file-only — no ENV interpolation, deliberately
(#3775). Only the deployment-wide switches (`JOBS_ENABLED`,
`JOBS_SCHEDULER_ENABLED`, `JOBS_FALLBACK_SYNC`) remain env-overridable.

## Ordering & fail-closed guarantee

`EntitlementMaterializeJob` performs its **own** catalog pull
(`Billing::Operations::Catalog::Pull`) at the start of every run and **aborts
unless that pull reports a verified catalog** — it never materializes from a
potentially stale cache. No verified pull, no materialize. This is the
invariant the production incident above violated: materializing against a
stale cache silently bakes the wrong entitlement set fleet-wide.

The gate is `Pull::Result#catalog_verified`, not `Pull::Result#success`.
`success` only means the pull ran without erroring; it is not a freshness
guarantee. When Stripe returns no matching products — wrong region filter,
unpublished products, no active recurring prices — the pull is a successful
no-op: it returns before pruning stale plans, before rebuilding the price-id
cache, and before stamping the sync timestamp, so the previously cached Redis
plans stay exactly as they were. `catalog_verified` is true only when the run
persisted at least one plan from the live Stripe catalog and completed that
prune/rebuild/timestamp path. Config-only deployments (no Stripe API key)
report `catalog_verified: false` as well — nothing was checked against
Stripe. Treating `success` as proof of freshness would let the job materialize
every org from a stale cache, which is the exact incident it exists to
prevent.

A nightly run that aborts with `catalog_pull_unverified` is the **safe**
outcome, not a degradation: entitlements are left exactly as they were, no
org's snapshot is rewritten, and the next run converges the fleet once the
catalog is readable again. Investigate the catalog, but there is no
entitlement damage to repair.

Consequence: the job does **not** depend on `PlanCacheRefreshJob` being
enabled or ordered before it. Enabling only the maintenance job is safe;
running both is the normal production posture (the 6h refresh keeps the cache
warm for the read path, the nightly job converges the materialized snapshots).

## Standalone mode (no Stripe API key)

Both jobs check `Onetime.billing_config.stripe_key` and skip gracefully when
it is empty — a DEBUG log line, no error. Standalone orgs get entitlements
from `materialize_standalone_entitlements` on the read path; there is no
Stripe catalog to converge against. It is safe to leave both flags enabled on
standalone installs.

## Deployment prerequisites

Neither job runs unless the **scheduler daemon** is running — full mode only:

```bash
bin/ots scheduler
```

Where it is wired:

- `Procfile.production` — the `scheduler: bin/ots scheduler` line is
  **commented out** by default; uncomment it in full auth mode.
- `etc/examples/systemd/onetimesecret-scheduler.service` — systemd unit
  example (`systemctl enable --now onetimesecret-scheduler`).
- `docker/compose/docker-compose.full.yml` — dedicated `scheduler` service
  (`./bin/ots scheduler --environment production`).

## Verify after deploy

1. **Scheduler logs at boot** — scheduling confirmations:

   ```
   [PlanCacheRefreshJob] Scheduling with interval: 6h
   [EntitlementMaterializeJob] Scheduling with cron: 0 3 * * *
   ```

   If a line is missing, the job's flag (or `jobs.maintenance.enabled`) is
   off in the config the scheduler process loaded.

2. **First runs.** `PlanCacheRefreshJob` fires ~1 minute after boot:

   ```
   [PlanCacheRefreshJob] Completed: N plans cached in Xms
   ```

   After the nightly cron, `EntitlementMaterializeJob` logs a single
   structured JSON report line at INFO with `plans_synced`, `scanned`,
   `succeeded`, `failed`, `skipped_no_plan`, `orgs_cascaded`,
   `memberships_succeeded`, `memberships_failed`, and `duration_ms`.
   Per-org failures are additionally logged at ERROR (capped at 20 entries);
   an aborted run reports `aborted: catalog_pull_failed`,
   `catalog_pull_raised`, or `catalog_pull_unverified` at ERROR.

   `catalog_pull_failed` and `catalog_pull_raised` mean the pull errored or
   raised — a Stripe outage, a bad API key, or a catalog validation failure.

   `catalog_pull_unverified` is different and is operator-actionable, not a
   job bug: the pull completed without error but returned no usable plans, so
   the job refused to materialize from the plans still sitting in the Redis
   cache. Check the catalog before assuming the job is broken:

   ```bash
   bin/ots billing catalog drift
   ```

   Look for a region filter that no longer matches any product (the `region`
   key in `etc/billing.yaml` vs the products' `region` metadata in Stripe),
   products that were unpublished or archived in Stripe, and products whose
   prices are no longer active recurring prices. Fix the catalog, then let
   the next nightly run converge — or re-run the manual path below.

3. **Catalog is clean:**

   ```bash
   bin/ots billing catalog drift    # config vs live Stripe; should report clean
   ```

4. **Orgs converged.** A fleet scan / colonel org detail should show
   "In sync / plan current"; per-org from the CLI:

   ```bash
   bin/ots org entitlement show <ORG>
   ```

## Manual / repair alternatives

All converge on the same idempotent operations the jobs use:

```bash
# Batch re-materialization, fleet-wide (dry-run by default; --run to execute):
bin/ots billing plans materialize --all --include-memberships
bin/ots billing plans materialize --all --include-memberships --run

# Single org — re-apply billing + entitlements:
bin/ots org reconcile <ORG> --dry-run
bin/ots org reconcile <ORG> --yes

# Catalog management (config vs Stripe vs Redis cache):
bin/ots billing catalog drift     # inspect config-vs-live drift
bin/ots billing catalog pull      # Stripe -> Redis plan cache
bin/ots billing catalog push      # config -> Stripe
bin/ots billing catalog sync      # push + pull
```

When repairing manually, follow the same ordering the job enforces: **pull
first, materialize second.**

The manual path has no `catalog_verified` gate — that check lives in the
job, not in `bin/ots billing catalog pull`. A pull that matches no products
reports success, syncs nothing, and leaves the previous plans cached, so
materializing straight afterwards is the incident, done by hand. Before
running `materialize`, confirm the pull actually synced plans:

```bash
bin/ots billing catalog pull      # must report a non-zero plan count
bin/ots billing catalog drift     # and no unexpected config-vs-live drift
```

If the pull reports zero plans, stop and fix the catalog first. Leaving org
entitlements untouched is always safer than materializing from plans you
did not just verify.

## Rollback

Both jobs are config-gated; no code change needed to back out:

- Set `jobs.maintenance.entitlement_materialize.enabled: false` (or the
  `jobs.maintenance.enabled` master toggle) and restart the scheduler to
  disable the nightly re-materialization.
- Set `jobs.plan_cache_refresh.enabled: false` likewise for the cache
  refresh.

Disabling both restores the previous webhook-only convergence behavior.
`MaterializePlans` is idempotent and preserves grants/revokes, so a bad run
is repaired by re-running against a correct cache
(`bin/ots billing catalog pull`, then
`bin/ots billing plans materialize --all --include-memberships --run`) — or
simply by letting the next nightly run converge it.
