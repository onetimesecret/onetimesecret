# Emit metrics from MaterializePlansResult for non-CLI callers

**Status:** Drafted (blocked posting to GitHub on auth refresh). Follow-up to [#3251](https://github.com/onetimesecret/onetimesecret/issues/3251).

**Labels:** improvement, backend, ruby

---

## Problem

`Billing::Operations::MaterializePlans` ([#3253](https://github.com/onetimesecret/onetimesecret/pull/3253)) was extracted from the CLI command specifically so non-CLI callers — background jobs, rake tasks, future admin UIs — can run the same batch materialization with consistent accounting and logging.

The operation returns a structured `MaterializePlansResult`:

```ruby
MaterializePlansResult = Data.define(
  :scanned, :succeeded, :failed,
  :skipped_no_plan, :skipped_plan_filter,
  :memberships_succeeded, :memberships_failed, :orgs_cascaded,
  :errors,
)
```

Today this result is consumed by exactly one caller: the CLI's `ProgressRenderer`. Every non-CLI caller would have to manually wire StatsD/Prometheus emission to get the same operational visibility — and there's nothing forcing them to. Result: any background job that ever runs this operation in production will silently lack the metrics the CLI operator has been relying on.

## Proposed change

Emit metrics from inside `MaterializePlans#call` (or via a small `BillingMetrics` collaborator) so every caller — CLI, background job, future admin UI — gets the same counters automatically.

At minimum:

| Metric | Type | Tags |
|---|---|---|
| `billing.materialize_plans.orgs.scanned` | counter | `dry_run`, `cascade` |
| `billing.materialize_plans.orgs.succeeded` | counter | `dry_run`, `cascade` |
| `billing.materialize_plans.orgs.failed` | counter | `dry_run`, `cascade` |
| `billing.materialize_plans.orgs.skipped` | counter | `reason` (`no_plan`, `plan_filter`) |
| `billing.materialize_plans.memberships.succeeded` | counter | — |
| `billing.materialize_plans.memberships.failed` | counter | — |
| `billing.materialize_plans.duration_ms` | histogram | `cascade` |

## Acceptance criteria

- A background-job caller of `MaterializePlans.call(...)` emits the metrics above with no additional plumbing.
- CLI behavior unchanged (renderer continues to consume the result; metrics fire in parallel).
- The metrics backend is whatever the rest of the app uses (TBD — confirm before implementing; if there is no existing telemetry pipe, this ticket may need to wait for or land alongside one).

## Out of scope

- Tracing (OpenTelemetry spans).
- Per-org timing breakdowns (the current granularity is the whole batch).
