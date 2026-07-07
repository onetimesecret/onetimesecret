---
labels: email-quality, phase-5, backend, frontend
depends: 20-suppression-model-and-gate, 31-bounce-complaint-handlers
epic: TBD
---

# Email quality: delivery-health counters, thresholds, events console

## Context

Part of the **Email Quality Controls** epic, Phase 5. Reputation management is
a control loop: the earlier slices act; this slice measures. Operators need to
see bounce/complaint/suppression rates BEFORE a provider or mailbox operator
notices them (Gmail/Yahoo expect complaint rates under 0.1%, alert-worthy well
below the 0.3% enforcement line), and support needs one place to answer "what
happened to mail for this address?".

## Scope

- **Counters** at the slice-20 choke point, beside `emails_sent` /
  `emails_suppressed`: class_counters `emails_hard_bounced`,
  `emails_soft_bounced`, `emails_complained`, `emails_rate_limited`,
  `emails_unsubscribed` (incremented by the slice-31 handlers and slice-50
  endpoint). Optional per-tenant breakdown: a `class_hashkey` keyed by
  `domain_id` for sends/bounces so a noisy tenant is identifiable — bounded by
  the custom-domain population, not unbounded keys.
- **`EmailHealthJob`** (`lib/onetime/jobs/scheduled/email_health_job.rb`,
  ScheduledJob, config block under `jobs:`): hourly, computes rolling
  bounce-rate and complaint-rate from counter deltas (state in a small Redis
  hash, no SCANs), logs a structured JSON report (`with_stats` style), WARNs +
  Sentry-notifies when thresholds crossed (`COMPLAINT_RATE_WARN = 0.1%`,
  `BOUNCE_RATE_WARN = 2%`, `BOUNCE_RATE_CRIT = 5%` — frozen constants with the
  DlqMonitorJob "loud in logs" posture; no auto-remediation).
- **Ops (read-only, no audit)**: `Onetime::Operations::Email::HealthReport`
  (rates + counter snapshot + suppression-list size + top suppression reasons)
  and the slice-21 `Events` op reused for the feed.
- **Colonel**: `GET /email/health` → stat tiles on the email-tools/suppressions
  screens (sends, suppressed, bounce rate, complaint rate, list size);
  `GET /email/activity` → recent global activity feed (from
  `EmailActivity.recent`, obscured addresses, bounded revrange). Zod schemas +
  locales as per slice 22 conventions.
- **CLI**: `bin/ots email health [--format json]` over the same op — the
  at-a-glance deliverability readout; wire a line into the existing colonel
  `/stats` payload if the dashboard already surfaces mailer counters.

## Grounding — files & pointers

- Counter precedent: `record_sent_metric` in `lib/onetime/mail/delivery/base.rb`; `Onetime::Customer.class_counter :emails_sent` (customer counter_fields feature)
- Scheduled-job template: `lib/onetime/jobs/scheduled/dlq_monitor_job.rb` (passive check + WARN), `heartbeat_job.rb` (interval stats); base `lib/onetime/jobs/scheduled_job.rb`; config shape in `etc/defaults/config.defaults.yaml` `jobs:`
- Global feed store: slice 20's `EmailActivity` `class_sorted_set :recent` (AdminAuditEvent revrange pattern, CONTRACT 6 bounded)
- Read-only op conventions: `lib/onetime/operations/ratelimit/inspect.rb` (no audit, bounded reads)
- Colonel stats wiring: existing `/info /stats` routes in `apps/api/colonel/routes.txt`; stat tiles per `docs/specs/colonel-ui/61-debt-stats-stubs.md` caveats (no stubbed tiles — real numbers or nothing)
- Sentry usage in jobs/workers: `lib/onetime/jobs/workers/base_worker.rb` trace helpers

## Acceptance criteria

- [ ] Rates computed from counter deltas only — the health path performs no
      KEYS/SCAN and no per-send extra writes beyond the existing choke-point
      increments.
- [ ] Threshold crossings WARN with actionable context (rate, window, counts)
      and notify Sentry once per crossing, not once per run (edge-triggered
      state in the job's Redis hash).
- [ ] Colonel tiles show live numbers; absent data renders as absent, never as
      zero-stubs (the 61-debt lesson).
- [ ] `bin/ots email health` and `GET /email/health` return identical figures
      (same op).
- [ ] Activity feed shows obscured addresses only; per-address drill-down goes
      through the slice-22 check form (hash translation).
- [ ] Job is enable/interval-configurable under `jobs:` and registers by file
      drop (scheduler auto-discovery); overlap-safe (read-mostly; the state
      hash write is last).

## Notes / risks

- Provider dashboards remain the ground truth for reputation; our rates are
  the early-warning proxy. Say so in the operator docs to prevent
  false confidence.
- Counters are monotonic and process-crash-safe (Redis INCR at the choke
  point); rate windows tolerate missed job runs by using timestamps in the
  state hash, not run counts.
- Don't add per-address counters — the per-hash activity timeline already
  covers drill-down, and unbounded per-address counter keys would violate the
  bounded-keys posture.
