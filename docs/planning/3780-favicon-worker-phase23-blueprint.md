# #3780 Phase 2 + Phase 3 Implementation Blueprint

**Status: SHIPPED.** Phase 2 (manual "Refresh favicon from domain" UI + `RefreshDomainFavicon`
endpoint) and Phase 3 (enqueue-on-add trigger + nightly `FaviconBackfillJob` with per-domain
backoff) were both built and merged via PR #3782 (2026-07-15), in the same PR as Phase 1. The
detailed build plan that used to live in this file (files to create/modify, ordered build
sequence, backoff-formula derivation, test plan) described work that is now done and has been
removed.

The seven open decisions this document originally raised (§5) were resolved as follows:

| # | Question | Resolution |
|---|----------|------------|
| 1 | Backoff schedule numbers | Shipped as recommended: `base_days=1`, `cap_days=30`, `max_attempts=6` (confirmed live in `etc/defaults/config.defaults.yaml:1294-1306`). |
| 2 | Enqueue-on-add given the domain is unverified | Shipped as specified — fires on add (`add_domain.rb`), double-fires safely with the verify-transition trigger via the idempotent overwrite guard. |
| 3 | Manual-refresh feature-flag gate | Shipped: gated on `jobs.favicon_fetch.enabled`, matching `verify_domain.rb`'s pattern. |
| 4 | UI button placement/shape | Went beyond the "bare button" recommendation — shipped as `BrandFaviconField.vue`, a full upload/replace/remove control with its own test coverage, alongside the refresh button in `SimpleBrandPanel.vue`. |
| 5 | Backfill coverage per run (large batch vs. cursor) | Resolved in code, not as originally framed: `FaviconBackfillJob` paginates the **full** domain set every run (a `loop` over `batch_size` pages, not just the newest page) — confirmed in `lib/onetime/jobs/scheduled/favicon_backfill_job.rb:85-107`. |
| 6 | Retry-of-"none-found" policy | Shipped: none-found domains ARE retried on the backoff schedule (not treated as terminal). |
| 7 | Does `FaviconBackfillJob.enabled?` require the worker flag | Shipped as specified (requires both `favicon_backfill.enabled` and `favicon_fetch.enabled`) — **but** a related gap was found in the post-merge audit: `enabled?` does *not* also check the master `jobs.enabled` gate, which allows a misconfiguration to run synchronous inline fetches on the scheduler thread. Tracked in `3780-favicon-worker-outstanding.md` §1 item 4. |

**Remaining work and gaps found in a post-merge audit** — including the flag-default
discrepancy, several still-open correctness findings from the pre-merge adversarial review, and
test-coverage gaps — are tracked in `3780-favicon-worker-outstanding.md`, now the live planning
document for this issue.
