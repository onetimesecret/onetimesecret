# Implementation Blueprint — #3780 Background worker: auto-fetch custom-domain favicon

**Status: SHIPPED.** This was the Phase 1 (core) implementation blueprint. Every item in it —
`SafeFetch`, `FetchDomainFavicon`, `FaviconFetchWorker`, the `domain.favicon.fetch` queue/DLQ,
`Publisher.enqueue_favicon_fetch`, the verify-transition trigger, storage/serving, and config
surface — was built and merged via PR #3782 (2026-07-15). The eight open questions this document
originally raised (§7) were all resolved; see `3780-favicon-worker-decisions.md` for the
decisions.

The step-by-step build plan (files to create/modify, build sequence, SSRF module design,
overwrite-policy design, config block, test plan) that used to live in this file described work
that is now done and has been removed — it added no ongoing value once the code it was
instructing how to write already exists. Read the current source directly instead:
`lib/onetime/http/safe_fetch.rb`, `lib/onetime/operations/fetch_domain_favicon.rb`,
`lib/onetime/jobs/workers/favicon_fetch_worker.rb`.

**Remaining work and gaps found in a post-merge audit** (correctness bugs, test-coverage gaps, a
feature-flag-default discrepancy, and documentation debt) are tracked in
`3780-favicon-worker-outstanding.md` — that is now the live planning document for this issue.
