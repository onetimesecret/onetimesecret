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
if the pull fails** — it never materializes from a potentially stale cache.
No pull, no materialize. This is the invariant the production incident above
violated: materializing against a stale cache silently bakes the wrong
entitlement set fleet-wide.

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
   an aborted run reports `aborted: catalog_pull_failed` (or
   `catalog_pull_raised`) at ERROR.

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
