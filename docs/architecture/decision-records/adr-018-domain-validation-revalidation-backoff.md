---
id: "018"
status: accepted
title: "ADR-018: Per-Domain Exponential Backoff Re-Validation (Reverses Stated Sampling Requirement)"
---

## Status

Accepted

## Date

2026-06-30

## Context

**This ADR records a reversal of a stated requirement.** The team asked for
"a background scheduled job for periodically re-validating a random
sampling of domains with a configurable percentage." The verified research
evidence does not support that design, and recommends a different one. This
is presented for explicit sign-off, not adopted silently.

Today, `lib/onetime/jobs/scheduled/domain_refresh_job.rb` is disabled by
default (`jobs.domain_refresh.enabled`, line 42) and, when enabled, does a
**full sweep** of every domain in batches of 200 every 30 minutes (lines 46,
71-75) — every domain gets the same fixed-interval treatment regardless of
its failure history, and there is no terminal state for a domain that never
resolves.

Cloudflare's Validation Backoff Schedule (corroborated by its own linked
mechanism doc) runs **per-domain** exponential backoff — intervals from 60s
up to a 4-hour cap, roughly 120 attempts over ~20 days — after which a
still-unresolved domain automatically transitions to a terminal state
(`Pending` → `Moved`/`Deleted`) rather than persisting indefinitely. RFC
8555 independently establishes, as a protocol-level norm, that ACME
authorization objects carry a mandatory expiry once valid — domain-ownership
proofs are inherently time-bounded artifacts in IETF's own design, not
one-time-forever facts. Neither system samples a percentage of its domain
population; both check every domain, on a per-domain schedule that adapts to
that domain's own history.

## Decision

Replace the full-sweep job with a **per-domain exponential backoff
scheduler**, not a percentage-sampled job:

- Each `CustomDomain` gains a `next_check_at` timestamp and a
  `consecutive_check_failures` counter.
- Newly-attached or recently-changed domains get short initial intervals
  (minutes), to detect a freshly-corrected DNS record quickly.
- Domains that have been stably `:verified` get long, lengthening intervals
  (hours to days) — most of the aggregate load reduction comes from not
  re-checking domains that haven't changed, not from skipping a percentage
  of the population at random.
- Repeatedly-failing domains back off exponentially, capped (mirroring
  Cloudflare's ~4h cap as a starting reference value, tunable), within a
  bounded total retry window (mirroring Cloudflare's ~20-day reference
  window, tunable to OTS's own scale).
- After the bounded window elapses without success, the domain transitions
  to an explicit terminal state (e.g. `stale`/`needs_attention`) surfaced to
  the customer as actionable — not silently stuck, and not checked forever.
  Re-entering the active check cycle requires an explicit customer action
  (re-trigger validation), consistent with ADR-016's ownership-axis model.
- The existing `domain_refresh_job` batch-sweep mechanism is retired in
  favor of this scheduler; `jobs.domain_refresh.enabled` and
  `check_interval` config keys are superseded by the new per-domain fields.

This also resolves the unbounded TXT-challenge lifetime noted in ADR-016's
implementation notes: the same bounded-window logic governs
`txt_validation_value` reuse, rather than adding a separate expiry
mechanism.

## Trade-offs

- **We lose**: the operational simplicity of one global job with two
  config knobs (enabled, interval). The scheduler carries per-domain state
  and more complex scheduling logic.
- **We gain**: lower aggregate DNS/API load than either the current
  full-sweep design or the originally-requested percentage-sample design
  (stable domains are checked far less often than either alternative would
  check them), faster detection of newly-fixed domains, and a defined exit
  for domains that will never resolve — directly addressing the "stuck
  forever" concern that motivated gating hesitancy in ADR-017.
- **Risk**: this is a larger implementation than a percentage-sample flag
  would have been. If the team prioritizes shipping speed over the
  research-backed design, the simpler percentage-sample job is still an
  option — but should be chosen knowingly, not by default, given the
  evidence above.

## Implementation Notes

### Requirement reversal — needs explicit sign-off (2026-06-30)

The original ask was percentage-based sampling; this ADR recommends
per-domain backoff instead, because that's what the verified evidence shows
comparable systems (Cloudflare, ACME/RFC 8555) actually doing. If the team
prefers to proceed with percentage-sampling anyway — e.g., for
implementation-simplicity reasons specific to OTS's current scale — that
should be recorded as a deliberate divergence in a follow-up note here, not
treated as the default outcome of reading this document.
