# #3780 — Resolved decisions & scope additions

**Status: SHIPPED.** All decisions below were implemented via PR #3782 (2026-07-15) — kept here
as the design-rationale record (why the overwrite guard, precedence, and trigger points behave the
way they do). Outstanding work and gaps found in a post-merge audit are tracked in
`3780-favicon-worker-outstanding.md`, not here.

Companion to `3780-favicon-worker-blueprint.md`. This file records the human decisions
on the blueprint's open questions and the mid-flight scope additions, verbatim.

## Resolved open questions (from blueprint §7)

| # | Question | Decision |
|---|----------|----------|
| 5 | Manual "refresh favicon" UI (Trigger B) — in scope? | **Include in this PR.** Build the Vue button + backend `RefreshDomainFavicon` endpoint. |
| 6 | HTTP vs HTTPS-only for the fetch | **HTTPS-only.** `ALLOWED_SCHEMES=['https']`, port 443 only. |
| 4 | Fetched-icon vs user-uploaded-logo precedence | **Only protect uploaded icon.** Auto-fetch may populate `icon` even when a user-uploaded logo exists; a fetched favicon then outranks the logo *as the favicon*. (The upload-overwrite guard still protects a user-uploaded **icon**.) |

Remaining open questions default as the blueprint recommends unless changed:
- Q1 trigger threshold → fire on **verified** (issue says "on domain-verification success").
- Q2 re-fetch policy → **skip auto-fetch when `icon` already holds an `auto_fetch` favicon**; manual refresh forces. Nightly scan (below) handles the not-yet-fetched set with backoff.
- Q3 ICO normalization → **passthrough, no native dep**.
- Q7 DLX naming → **new `dlx.domain.favicon` / `dlq.domain.favicon`**.
- Q8 persistence primitive → verify `CustomDomain#save_fields` + loader during impl.

## Scope additions (user request, verbatim)

> So when appropriate, a couple additions once we have the new worker and test coverage:
> - An operation that implements the logic.
> - a job is queued when a domain is added.
> - a nightly job that scans for custom domains without a favicon and queues up a job for each one. ideally with backoff similar to our domain validation so that we don't check every night forever for a domain that has no favicon to get.

All three phases below (operation, enqueue-on-add, nightly backoff scan) shipped in PR #3782. The
per-phase build sequencing that used to be listed here described completed work and has been
removed; see `3780-favicon-worker-outstanding.md` for what's left.
