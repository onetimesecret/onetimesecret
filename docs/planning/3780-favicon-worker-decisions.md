# #3780 — Resolved decisions & scope additions

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

### Interpretation / sequencing

Build order — additions land **after** the core worker + test coverage are green:

1. **Operation** — `Onetime::Operations::FetchDomainFavicon`. Already in the blueprint core (the unit of work shared by worker + inline fallback). ✔ Core.
2. **Enqueue on domain add** — fire `enqueue_favicon_fetch(domain_id)` at custom-domain creation (in addition to the verification-success trigger), feature-flag gated. New trigger point beyond the blueprint.
3. **Nightly backoff scan** — a scheduled job that finds custom domains with no `auto_fetch` favicon and whose backoff window has elapsed, and enqueues a fetch for each. Backoff mirrors domain-validation so we stop retrying domains that never yield a favicon.
   - Requires backoff bookkeeping on `CustomDomain`: attempt counter + `favicon_fetch_next_at` (or equivalent), incremented on empty/failed outcomes; cleared on success.
   - Mirror the existing `domain_refresh_job` / expiration-warnings scheduled-job mechanism.

## Build phases

- **Phase 1 (core):** SafeFetch + operation + worker + queue/publisher + storage/serving + config + trigger-on-verify + tests. *(this workflow)*
- **Phase 2:** Manual refresh UI (backend endpoint + Vue).
- **Phase 3:** Enqueue-on-add trigger + nightly backoff scan + backoff fields.
