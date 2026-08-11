# #3780 — Favicon fetch worker: outstanding work & opportunities

**Date:** 2026-08-11
**Status of #3780 itself:** Implemented and merged (PR #3782, 2026-07-15). This document
supersedes `3780-favicon-worker-blueprint.md`, `3780-favicon-worker-decisions.md`, and
`3780-favicon-worker-phase23-blueprint.md` as the tracker for what's left — those three now
describe completed work and have been trimmed to short historical pointers.

**Tracking issue: #4135.** Every item below is mirrored as a checkbox on
[#4135](https://github.com/onetimesecret/onetimesecret/issues/4135) — check items off in both
places as they land, and keep this document in sync with that issue.

Produced by a code-verified audit (8 independent agents, each finding checked directly against
the current tree, not against the original adversarial-review comment's claims) run against the
current codebase on 2026-08-11. Every item below cites file:line evidence; see the audit for the
full trace if needed.

## 0. Read this first: the flag-default contradiction

**`jobs.favicon_fetch.enabled` currently defaults to `true`** (`etc/defaults/config.defaults.yaml:1275`,
comment: *"Feature flag — default ON (see #3780)"*). This directly contradicts:
- Issue #3780's own Definition of Done: *"Feature flag defaults off"*.
- PR #3782's description: *"Flag-gated OFF (`jobs.favicon_fetch`) — no runtime behaviour changes
  until enabled."*

`jobs.favicon_backfill.enabled` (the nightly scan) correctly still defaults to `false`
(`config.defaults.yaml:1296`), so the nightly-scan-specific bugs below (#2, #4, #5) are only live
once an operator flips that second flag. But the fetch-on-add, fetch-on-verify, and manual-refresh
triggers are live **today**, by default, on every deployment that also has `jobs.enabled: true`
(or run inline-synchronously on the request/verification thread when `jobs.enabled` is `false`,
which is itself the default — see `config.defaults.yaml:1179`).

This matters because the original adversarial-review comment on the issue graded several findings
as low/medium severity partly *because* it assumed the feature was dormant ("none of these are
live production defects at present"). With the flag on by default, that assumption no longer
holds — items #1–#3, #6–#9 below are current-severity, not hypothetical.

**Action needed:** a maintainer decision — was flipping `favicon_fetch.enabled` to `true` by
default intentional? If yes, the issue's DoD, the PR description, and `docs/runbooks/favicon-fetch-worker.md`
all need updating to match (§5 below). If no, revert to `false` and treat re-enabling as a
separate, deliberate rollout decision once items #1–#9 are addressed.

---

## 1. Correctness & reliability — outstanding

These are the review findings that were checked against current code and are **still present**.
Findings the review raised that have since been fixed are *not* listed here (see §7).

1. **Perpetually-timing-out domains bypass the attempt cap.** `favicon_fetch_attempts` is
   incremented only by `record_none_found`/`record_failure`
   (`lib/onetime/operations/fetch_domain_favicon.rb:345-379`); the `SafeFetch::FetchTimeout`
   rescue (`:152-159`) re-raises without stamping anything. A host that always times out never
   trips `max_attempts` and (once `favicon_backfill` is enabled) is re-enqueued every night
   forever. No regression test exists for the attempts counter on the timeout path either
   (`fetch_domain_favicon_try.rb:248-261` asserts status only, not attempts).

2. **`requeue!` is a dead retry tier.** `claim_for_processing` (`base_worker.rb:250-255`) is never
   released on the timeout/requeue path in `favicon_fetch_worker.rb` — contrast
   `session_revocation_sweep_worker.rb:110-118`, which calls `release_processing_claim` before
   `reject!` specifically to avoid this trap. A broker redelivery of the same message within the
   1h idempotency TTL is silently ack'd as a "duplicate" and never reprocessed; the domain stalls
   at `PROCESSING` until the next nightly backfill (if enabled) or forever (if not).

3. **No per-domain exception isolation in the nightly scan.** `favicon_backfill_job.rb:85-113`
   wraps the *entire* scan (all pages) in one `rescue StandardError`. The pagination design itself
   is correct — it loops through the full domain set in `batch_size` pages (`:92-107`), not just
   the newest page — but one bad domain or a transient publish error mid-scan aborts everything
   after it for that run, undermining the full-coverage design.

4. **`FaviconBackfillJob.enabled?` omits the master `jobs.enabled` gate.** It checks only
   `favicon_backfill.enabled` and `favicon_fetch.enabled` (`favicon_backfill_job.rb:62-65`). An
   operator who flips `favicon_backfill.enabled=true` without also setting the master
   `JOBS_ENABLED=true` gets synchronous, blocking SSRF-guarded fetches run inline on the
   rufus-scheduler thread for up to `batch_size` (500) domains per run.

5. **Wall-clock deadline doesn't cover the header/status-line read.** `check_deadline!` is called
   only at fetch-entry and per body chunk (`lib/onetime/http/safe_fetch.rb:139,298`); the
   status-line/header read inside `with_pinned_response` (`:262-265`) has no deadline check. A
   server that dribbles response headers one byte at a time can pin a worker thread indefinitely —
   a live worker-starvation surface now that the flag defaults on.

6. **`favicon_fetch_*` fields on the main `CustomDomain` hash risk being wiped by unrelated full
   `domain.save` calls.** These six fields are declared as plain `field`s on the main object hash
   (not a sub-hashkey), specifically to avoid racing the icon write — but `verify_domain.rb:332`,
   `add_domain.rb:142`, and several other writers still call a full `.save` on the same object.
   Whether Familia's stale-nil-field cleanup actually HDELs these on such a save could not be
   confirmed against the installed gem in this environment; the code-level exposure is unchanged
   from the original design and untested either way.

7. **No rate limiting on the manual refresh endpoint.** `POST /:extid/icon/refresh`
   (`refresh_domain_favicon.rb`) always passes `force: true`, bypassing the attempt cap, backoff
   window, and existing-icon guard that protect the automated path — and has no cooldown of its
   own. Any authenticated org member with `manage_org` + `custom_branding` can trigger repeated
   outbound SSRF-guarded fetches with zero throttle. (Auth/entitlement-gated, not anonymous —
   this lowers but doesn't remove the concern.)

8. **Idempotency is keyed on `message_id`, not `domain_id`.** Two independent enqueues for the
   same domain (e.g. a nightly-scan enqueue racing a manual force-refresh) can run concurrently;
   the attempts/backoff counters are a plain read-modify-write, not an atomic increment, so
   concurrent terminal writes can lose an increment.

9. **Crash window between `write_icon` and `record_success`.** These are two separate, non-atomic
   persistence steps (`fetch_domain_favicon.rb:135-137`). A crash between them leaves an
   `auto_fetch` icon stored but `favicon_fetch_status` stuck at `processing` forever — the
   overwrite guard then silently skips all future attempts without ever correcting the stuck
   status.

10. **Deferred, tracked separately:** JPEG/WebP normalization for uploaded (non-fetched) icons
    remains an explicit TODO (`apps/web/core/logic/page/get_favicon.rb:146`) — non-PNG uploads are
    served at original size instead of resized to the 32×32 favicon dimension. Low priority;
    ICO passthrough (the #3780-specific case) is done.

## 2. Test-coverage gaps

None of these represent a known-wrong runtime behavior by themselves (code inspection shows the
guarded behavior is correct in most cases) — they're regression risk: a future refactor could
silently reopen the corresponding bug with the full suite staying green.

11. **`force: true` against a `user_upload`/legacy icon is untested.** The guard logic is correct
    by inspection (`fetch_domain_favicon.rb:180-203`, the source check runs before the force
    check), but no test exercises this specific combination
    (`fetch_domain_favicon_try.rb` only tests force+`auto_fetch`, and `user_upload`/legacy without
    force).
12. **The worker's real `favicon_fetch_enabled?` config-dig path is never exercised** —
    `favicon_fetch_worker_spec.rb:138` stubs the method in every example, including the
    "disabled" context.
13. **The DNS-rebinding pin (`http.ipaddr =`) and TLS `verify_mode` are only exercised via a
    stubbed transport seam** (`safe_fetch_try.rb`'s `StubFetch` overrides
    `with_pinned_response` entirely) — a deliberate hermetic-testing tradeoff, but it means the
    single most security-critical line in the module has zero regression protection.
14. **Relative/protocol-relative redirect `Location` absolutization is untested** — every redirect
    test uses a fully-qualified URL; `#absolutize`'s relative-path and `//host/` branches are
    never hit.
15. **Teredo (`2001:0000::/32`) is missing from `BLOCKED_V6`** — the same class of tunneling
    prefix as the already-blocked 6to4 (`2002::/16`) and NAT64 (`64:ff9b::/96`) ranges, but
    omitted. Narrow, defense-in-depth gap (requires the fetching host to have Teredo transport
    configured).
16. **No test drives an actual broker redelivery** of a requeued message through
    `work_with_params` a second time — the existing test only asserts the worker *calls*
    `requeue!`, not that a redelivery is handled correctly (it currently isn't — see #2).
17. **No genuine end-to-end integration test.** Every layer (operation, worker, `GetFavicon`) is
    tested in isolation with stubs; nothing enqueues a fetch, lets it run, and confirms
    `GetFavicon` serves the resulting bytes for the same domain.
18. **`GetFavicon`'s ICO-serving branch is untested on the serve side.** The operation's ICO
    write is tested; no test seeds an ICO `content_type` and confirms `GetFavicon` takes the
    `ICO_CONTENT_TYPES` branch and serves the bytes unmodified.
19. **The frontend disable-gate's derivation from a real domain record is untested** — the only
    component test passes `faviconSource` as a hardcoded prop. The one test that exercises the
    real chain (`DomainBrand.vue` → `useDomain` → `SimpleBrandPanel`) is
    `e2e/full/domain-favicon-refresh.spec.ts` TC-FAV-002, which is dormant in CI (gated behind
    `E2E_CUSTOM_DOMAINS`, tracked under #3420).

## 3. UX gap

20. **No in-UI feedback on refresh outcome.** The refresh button shows an unconditional "queued"
    toast regardless of what happens afterward; nothing polls or re-fetches the icon, so a user
    can't tell from the UI whether the fetch succeeded, found nothing, failed, or was silently
    skipped by the overwrite guard. (Previously accepted as a known tradeoff — flagging again here
    because the feature is now live by default, so this failure mode is reachable in production
    today, not hypothetical.)

## 4. Documentation debt

21. **`docs/runbooks/favicon-fetch-worker.md` says the flag is "disabled by default" / `false`.**
    This is the primary operational runbook for the feature and its central framing is now wrong
    (see §0). Needs updating regardless of which way the flag-default decision goes.
22. **Same doc says the refresh endpoint "still returns a queued success" when the flag is off** —
    it actually returns an "unavailable" message (`refresh_domain_favicon.rb:78`). Stale from an
    earlier implementation pass.
23. **`docs/product/branding-favicon.md` never mentions the auto-fetch capability at all.** Its
    per-domain-icon precedence section still says only *"uploaded per domain"* — silent on the
    now-live fetch path. This is the doc most likely to be read by someone asking "how does a
    custom domain get its favicon."
24. **`docs/product/branding-favicon.md` and #3780's own docs never cross-reference each other**,
    despite touching the same per-domain-icon precedence chain (brand-pack v2 / #3774 vs.
    favicon-fetch / #3780). An opportunity to document the full precedence chain — fetched icon >
    uploaded icon > uploaded logo > brand-pack override > tracked default — in one place.
25. **`docs/specs/brand-manager/brand-manager-favicon-support.md` is stale.** It predates the PR
    merge and states *"there are no favicon API endpoints yet"* — no longer true. Should be
    archived or updated to reflect the shipped state.
26. **No CHANGELOG entry.** `changelog.d/` has active, current fragments (through 2026-08-10 for
    unrelated issues) but nothing for #3780/#3782, despite this being a behavior change live by
    default for every deployment (outbound fetches to every custom domain).

## 5. Related work not defined by #3780 but that should be completed

- Resolve the flag-default question (§0) and make the DoD / PR description / runbook consistent
  with whatever is decided.
- Add the missing regression tests in §2, prioritizing #11 (force+user_upload — protects user
  content), #16/#2 (requeue/redelivery — data availability), and #17 (end-to-end — the only thing
  that actually proves the feature works as a whole).
- Fix items #1–#9 in §1, roughly in the order they're likely to bite: #2 (silent message drop) and
  #5 (worker-pinning) first since they're live today regardless of `favicon_backfill`; #1, #3, #4
  matter once the nightly scan is turned on.
- Get `E2E_CUSTOM_DOMAINS` unblocked in CI (tracked under #3420) so
  `domain-favicon-refresh.spec.ts` actually runs — it's the only test that would catch a
  regression in the real `DomainBrand.vue` → `useDomain` → `SimpleBrandPanel` derivation chain.
- Write the CHANGELOG fragment and update the three docs in §4.

## 6. Related opportunities (adjacent, not required)

- **#3550 (branding polish, still open, milestone v0.26)** is thematically adjacent — it's about
  OTS branding leaking into neutral/custom-domain surfaces and logo/mark fallback precedence. No
  in-repo textual link exists between #3550 and #3780/#3782 in either direction, and no code
  coupling was found. Worth a look: the decisions doc's Q4 resolution ("a fetched favicon may now
  outrank a user-uploaded *logo* as the favicon, even though it can never overwrite a
  user-uploaded *icon*") is exactly the kind of precedence-correctness question #3550 catalogs
  elsewhere in the branding subsystem — someone auditing #3550 should know this exists.
- Unify the per-domain icon precedence documentation across `docs/product/branding-favicon.md`
  (#3774/#3739 static pack) and the favicon-fetch feature (#3780) — see item #24.

## 7. Unrelated opportunities

None surfaced. The audit agents were scoped tightly to the favicon-fetch feature and its
immediate neighbors and were instructed not to go looking outside that area; nothing incidental
worth flagging came up.

## Appendix — what's already done (no action needed)

For completeness, the audit also confirmed the following are implemented correctly and don't need
further work: the core SSRF acceptance criteria (private/link-local/metadata blocking including
via redirect, redirect cap, timeouts, max-size, content-type/magic-byte validation, SVG
rejection); the single-status worker lifecycle shape; worker auto-discovery and queue/DLQ wiring
(including automatic appearance in `ots queue status`); the nightly backfill job's full-population
pagination; the `force`+`user_upload` overwrite-guard *logic* (only its test coverage is missing,
see #11); ICO passthrough serving; the `RefreshDomainFavicon` enqueue-isolation fix; and — notably
exceeding the original design — the frontend provenance wiring (`safe_dump` → Zod → Vue disable
gate) which now ships with a dedicated schema-drift regression test, and `BrandFaviconField.vue`,
a fully-realized upload/replace/remove control that goes well beyond the "bare button" the
phase 2/3 blueprint scoped.
