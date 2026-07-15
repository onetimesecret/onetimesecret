All anchors in the maps verified against source — line numbers, signatures, and the critical facts (Publisher does NOT thread `force`; jobs-disabled inline branch is unrescued; terminal recorders at 316/326/336; add-callsite at 100-118) are all accurate. Here is the consolidated blueprint.

---

# #3780 Phase 2 + Phase 3 Implementation Blueprint

Phase 1 shipped: `SafeFetch`, `FetchDomainFavicon(force:)`, `FaviconFetchWorker`, `domain.favicon.fetch` queue, `Publisher.enqueue_favicon_fetch`, verify-transition trigger, and the four `favicon_fetch_*` fields on `CustomDomain`.

## Identity invariant (applies everywhere)
The arg passed to `Publisher.enqueue_favicon_fetch` and `FetchDomainFavicon` is the **CustomDomain identifier == `domainid` == `objid`** (`custom_domain.rb:79` `identifier_field :domainid`, alias `:160`), **never the route `extid`**. `FetchDomainFavicon#resolve_domain` does `CustomDomain.load(@domain_id)` (`:170`). At the API boundary you get `@custom_domain` from `authorize_domain_config!(@extid)` (loads by extid), then pass `@custom_domain.identifier`.

---

## 1. Phase 2 — Manual "Refresh favicon from domain"

**Goal:** a POST endpoint + UI button that enqueues a `force: true` fetch. Requires threading `force` through the Publisher (worker already reads `data[:force]`).

### Backend (agent: **backend-dev**)

**B1 — Thread `force` through the Publisher.** `lib/onetime/jobs/publisher.rb`. Both methods currently take only `domain_id` (verified: class `:134`, instance `:361`; inline call `:368` has no `force`; payload `:373-376` has no `force`).

- Class method `:134`:
  ```ruby
  def enqueue_favicon_fetch(domain_id, force: false)
    new.enqueue_favicon_fetch(domain_id, force: force)
  end
  ```
- Instance method `:361`: add `force: false` param; pass into the inline fallback at `:368` → `FetchDomainFavicon.new(domain_id: domain_id, force: force).call`; add `force: force` to the message hash at `:373`.

This is backward-compatible: existing callers (`verify_domain.rb:353`, and Phase 3a add-callsite) omit `force` and get `false`.

**B2 — New logic class `RefreshDomainFavicon`.** Create `apps/api/domains/logic/domains/refresh_domain_favicon.rb`, copying the shape of `remove_domain_image.rb` (write-path: `include DomainConfigAuthorization`, `config_entitlement = 'custom_branding'`).

- `process_params`: `@extid = sanitize_identifier(params['extid'])`
- `raise_concerns`: `raise_form_error 'Domain ID is required' if @extid.empty?`; `raise_form_error 'Invalid domain identifier format' unless @extid.match?(/\A[a-z0-9]+\z/)`; `authorize_domain_config!(@extid)` (this loads `@custom_domain`, `@organization`, enforces `manage_org` + `custom_branding` + per-member domain scope); `@greenlighted = true`
- `process`:
  ```ruby
  Onetime::Jobs::Publisher.enqueue_favicon_fetch(@custom_domain.identifier, force: true)
  success_data
  ```

**Feature-flag decision (see §5):** recommended to mirror `verify_domain.rb:351` — gate the enqueue behind `OT.conf.dig('jobs','favicon_fetch','enabled') == true`. Without the gate and with jobs disabled, `process` runs an inline synchronous DNS+HTTPS fetch on the request thread (`publisher.rb:362-368`). Since the manual button is user-initiated, a short block may be acceptable, but the flag-gate keeps behavior consistent with the auto path.

**B3 — Register route + namespace.**
- `apps/api/domains/routes.txt`: add next to the icon rows (`:21-23`):
  ```
  POST   /:extid/icon/refresh   DomainsAPI::Logic::Domains::RefreshDomainFavicon response=json auth=sessionauth,basicauth
  ```
- `apps/api/domains/logic/domains.rb`: add `require_relative 'domains/refresh_domain_favicon'`.

### Frontend (agent: **frontend-dev**)

The store has **only logo actions** today (no icon actions) — this is net-new.

**F1 — Store action.** `src/shared/stores/domainsStore.ts`: mirror `verifyDomain` (~L197). Add `async function refreshFavicon(extid: string) { await $api.post(`/api/domains/${extid}/icon/refresh`); }`; add to `DomainsStore` type and the returned action map.

**F2 — Composable callback.** `src/shared/composables/useBranding.ts`: mirror `removeLogo`:
```ts
const refreshFavicon = async () => wrap(async () => {
  const extid = resolveExtid(domainId);
  await domainsStore.refreshFavicon(extid);
  notifications.show(t('...favicon-refresh-queued'), 'success', 'top');
  return true;
});
```
Export it. Note `wrap()` toasts on failure and resolves `undefined`; return truthy on success.

**F3 — UI wiring.** `src/apps/workspace/domains/DomainBrand.vue` destructures `refreshFavicon` from `useBranding(props.extid)` and threads it via `BrandEditor` → `SimpleBrandPanel` (`src/apps/workspace/components/dashboard/brand/SimpleBrandPanel.vue`) as `onRefreshFavicon`. Simplest home: a "Refresh favicon from domain" button as a sibling of `BrandLogoField`. Optional richer form: new `BrandFaviconField.vue` mirroring `BrandLogoField.vue` with an icon thumbnail (requires loading `iconImage` in `useBranding` — only `logoImage` is loaded today).

**Async semantics:** the POST returns `{ queued: true }`-style immediately; the new icon lands later via the worker. UI should show a "refreshing" state and re-fetch the icon / poll `favicon_fetch_status` rather than expect bytes in the response. **Overwrite-guard UX:** `force: true` still will NOT overwrite a `user_upload` (or legacy untagged) icon (`fetch_domain_favicon.rb` overwrite_guard). The button is only meaningful when the icon is empty or `auto_fetch` — disable it or show an explanatory toast otherwise.

---

## 2. Phase 3 — enqueue-on-add + nightly backoff scan

### (a) Enqueue-on-add (agent: **backend-dev**)

`apps/api/domains/logic/domains/add_domain.rb`, in `#process`. Insert **after** the `request_certificate` begin/rescue (ends `:116`) and **before** `success_data` (`:118`). The class already `include Onetime::LoggerMethods` (`:29`), so `logger.error` is in scope.

**The begin/rescue is MANDATORY** — `Publisher.enqueue_favicon_fetch`'s jobs-disabled branch (`publisher.rb:362-368`) runs `FetchDomainFavicon.new(...).call` unrescued, and that `.call` re-raises `FetchTimeout` (`fetch_domain_favicon.rb:155`) and `StandardError` (`:163`). Jobs are disabled in dev/test (the default), so an unwrapped enqueue would break domain creation.

```ruby
# Auto-fetch the domain's favicon on add (#3780). Flag-gated and isolated:
# the Publisher's jobs-disabled branch runs FetchDomainFavicon inline and can
# raise, so wrap so a favicon failure never breaks add.
if OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true
  begin
    Onetime::Jobs::Publisher.enqueue_favicon_fetch(@custom_domain.identifier)
  rescue StandardError => ex
    logger.error '[AddDomain] Failed to enqueue favicon fetch',
      display_domain: @display_domain, exception: ex
  end
end
```

Use `@custom_domain.identifier` (populated from `:100`), not `@display_domain`. Recommend the **inline block** (matches the local `request_certificate` idiom) over extracting a helper, unless you also reuse it. Double-fire with the verify-transition enqueue (`verify_domain.rb:161-163`) is expected and safe — the overwrite_guard makes the second run an idempotent no-op.

### (b) New CustomDomain backoff fields + backoff computation

**There is no existing persisted backoff to mirror** (confirmed: `vhost_fetch_failed_at` is written but never read for skip decisions; `MailerConfig#check_recent?` is dead code + flat TTL; `RetryHelper` is in-process seconds-scale). You must build it.

Add to `custom_domain.rb` after the existing favicon fields (`:102-105`):
```ruby
field :favicon_fetch_attempts # integer count of terminal non-success attempts
field :favicon_fetch_next_at  # epoch seconds; earliest eligible re-fetch time
```

**Backoff formula** — `RetryHelper.compute_delay` (`base * 2^(n-1) + jitter`) converted to days, capped, with a permanent stop:
```
next_at   = now + min(base_days * 2^(attempts-1), cap_days) * 86400  (+ jitter)
```
Recommended concrete schedule (product decision flagged in §5): `base_days=1`, `cap_days=30`, `max_attempts=6`. Yields retry offsets 1d → 2d → 4d → 8d → 16d → 30d(cap), then stop (leave `favicon_fetched=false`, don't re-enqueue). Config knobs under a new `jobs.favicon_backfill` block.

### (c) FetchDomainFavicon terminal-recorder changes (agent: **backend-dev**)

`lib/onetime/operations/fetch_domain_favicon.rb`. Increment/schedule backoff on non-success terminal outcomes; clear on success.

- `record_success` (`:316`): reset backoff — set `favicon_fetch_attempts = 0`, `favicon_fetch_next_at = nil`; add both to the `save_fields` list.
- `record_none_found` (`:326`): `favicon_fetch_attempts = attempts+1`; compute+set `favicon_fetch_next_at` via the formula (stop scheduling once at cap); add both to `save_fields`.
- `record_failure` (`:336`): same increment + `next_at` computation; add both to `save_fields`.

Read backoff config with `OT.conf.dig('jobs','favicon_backfill',...)` and explicit defaults (jobs subtree is not in the in-code DEFAULTS hash — every read must fall back and treat non-`true` as off).

### (d) Nightly scheduled scan (agent: **backend-dev**)

**Recommendation: a separate `FaviconBackfillJob`**, not an extension of `DomainRefreshJob`. Extending `DomainRefreshJob` (`domain_refresh_job.rb`) couples favicon cadence (daily + backoff) to domain-refresh cadence (30m interval) and that job does zero per-domain skip filtering.

New file `lib/onetime/jobs/scheduled/favicon_backfill_job.rb` — auto-discovered by `SchedulerCommand#load_scheduled_jobs` (globs `scheduled/**/*_job.rb` + `ObjectSpace`; **no manual registration**; filename MUST end `_job.rb` and `.schedule` MUST be overridden). Copy `domain_refresh_job.rb` structure; use `cron()` (nightly) not `every()`.

```ruby
# frozen_string_literal: true
require_relative '../scheduled_job'
require_relative '../publisher'
require_relative '../workers/job_lifecycle'

module Onetime
  module Jobs
    module Scheduled
      class FaviconBackfillJob < ScheduledJob
        JobLifecycle       = Onetime::Jobs::Workers::JobLifecycle
        DEFAULT_CRON       = '0 3 * * *'
        DEFAULT_BATCH_SIZE = 500
        STUCK_PROCESSING_S = 3600  # older than worker requeue window

        class << self
          def schedule(scheduler)
            return unless enabled?
            scheduler_logger.info "[FaviconBackfillJob] Scheduling with cron: #{cron_pattern}"
            cron(scheduler, cron_pattern) { backfill_favicons }
          end

          private

          def enabled?
            # depends on BOTH gates: no point enqueuing if the worker drops messages
            OT.conf.dig('jobs', 'favicon_backfill', 'enabled') == true &&
              OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true
          end

          def cron_pattern
            OT.conf.dig('jobs', 'favicon_backfill', 'cron') || DEFAULT_CRON
          end

          def batch_size
            n = OT.conf.dig('jobs', 'favicon_backfill', 'batch_size').to_i
            n.positive? ? n : DEFAULT_BATCH_SIZE
          end

          def backfill_favicons
            ids     = Onetime::CustomDomain.instances.revrangeraw(0, batch_size - 1)
            domains = Onetime::CustomDomain.load_multi(ids).compact
            now = Familia.now.to_i
            enqueued = 0
            domains.each do |d|
              next unless eligible?(d, now)
              Onetime::Jobs::Publisher.enqueue_favicon_fetch(d.identifier)
              enqueued += 1
            end
            scheduler_logger.info "[FaviconBackfillJob] Scanned #{domains.size}, enqueued #{enqueued}"
          rescue StandardError => ex
            scheduler_logger.error "[FaviconBackfillJob] Unexpected error: #{ex.class} - #{ex.message}"
            scheduler_logger.error ex.backtrace.first(5).join("\n") if OT.debug?
          end

          # Eligible = lacks an auto_fetch favicon AND next_at elapsed AND not
          # a fresh in-flight processing AND under the attempt cap.
          def eligible?(d, now)
            return false if d.favicon_fetched == true                     # icon already stored
            src = d.icon['favicon_source'].to_s
            return false if !src.empty? && src != 'auto_fetch'            # user_upload/legacy — guard skips anyway
            return false if d.favicon_fetch_attempts.to_i >= max_attempts # permanent stop
            # stuck-processing: PROCESSING is only "in flight" if recently stamped
            if d.favicon_fetch_status == JobLifecycle::PROCESSING
              last = d.favicon_fetch_completed_at.to_i
              return false unless last.positive? && (now - last) >= STUCK_PROCESSING_S
            end
            nxt = d.favicon_fetch_next_at.to_i
            nxt.zero? || nxt <= now                                       # never scheduled, or backoff elapsed
          end

          def max_attempts
            n = OT.conf.dig('jobs', 'favicon_backfill', 'max_attempts').to_i
            n.positive? ? n : 6
          end
        end
      end
    end
  end
end
```

**Config block** — `etc/defaults/config.defaults.yaml`, inside the `jobs:` tree (after `favicon_fetch:`, ~L960):
```yaml
  favicon_backfill:
    enabled: <%= ENV['JOBS_FAVICON_BACKFILL_ENABLED'] == 'true' || false %>
    cron: '0 3 * * *'
    batch_size: 500
    max_attempts: 6
    base_days: 1
    cap_days: 30
```

**Stuck-PROCESSING trap (must handle):** `fetch_domain_favicon.rb#mark_processing` (`:311`) stamps `PROCESSING` **before** the network call; on `FetchTimeout` it re-raises with **no terminal stamp** (`:155`) and the worker `requeue!`s. If broker retries exhaust / message is DLQ'd, `favicon_fetch_status` is stuck at `processing` forever with no `completed_at`. The `STUCK_PROCESSING_S` clause above re-enqueues those; the threshold must exceed the worker's total requeue window (`with_retry 2x` + broker redelivery).

**Pagination caveat:** a single run scans only the newest `batch_size` domains (`instances.revrangeraw(0, batch_size-1)`), identical to `domain_refresh_job`. For a population > `batch_size` you need either a large batch or a cursor across nights — flagged in §5.

---

## 3. Ordered build sequence

Two parallel tracks (backend-dev, frontend-dev). Within backend, three independent sub-threads.

```
BACKEND (backend-dev)
  B1  Publisher force: threading .............. blocks B2
  B2  RefreshDomainFavicon logic + route + require ... depends B1
  ── parallel with B1/B2 ──
  B3  enqueue-on-add rescue-wrapped block ..... independent (uses no-force call)
  ── parallel with B1/B2/B3 ──
  B4  CustomDomain fields + FetchDomainFavicon backoff writes ... blocks B5
  B5  FaviconBackfillJob + config block ....... depends B4

FRONTEND (frontend-dev)  — parallel with entire backend track
  F1  domainsStore.refreshFavicon ............. contract known from B2 route
  F2  useBranding.refreshFavicon .............. depends F1
  F3  DomainBrand → SimpleBrandPanel button ... depends F2
```

**Critical path:** B1 → B2 → (integration test with F1–F3). **Parallelizable:** B3, B4→B5, and the whole frontend track run concurrently with B1→B2. B3 has no dependency on B1 (it uses the existing no-`force` signature; safe whether B1 lands first or not). Frontend can be built against the known POST contract before B2 merges; end-to-end verification waits for B2.

---

## 4. Test plan (tryouts + specs)

**Ruby — tryouts v3** (`try --agent`):

| Behavior | Test |
|---|---|
| B1 Publisher threads `force` | Tryout: `enqueue_favicon_fetch(id, force: true)` with jobs disabled → asserts inline `FetchDomainFavicon` receives `force: true`; jobs enabled → message hash includes `force: true`. Extend the existing publisher tryout. |
| B2 RefreshDomainFavicon | Tryout: valid extid + entitled member → enqueues with `@custom_domain.identifier`, `force: true`, returns `success_data`; bad extid format → form error; no `custom_branding` → authz error; cross-org domain → denied. Mirror the `remove_domain_image` tryout. |
| B3 enqueue-on-add | Tryout on `AddDomain#process`: jobs-disabled + `FetchDomainFavicon` stubbed to raise `FetchTimeout` → domain still created, `success_data` returned, error logged (proves the rescue). Flag off → no enqueue. |
| B4 backoff fields + math | Tryout on `FetchDomainFavicon`: `record_none_found` → `attempts` increments, `next_at ≈ now + base_days*86400`; second none-found → `next_at ≈ now + 2d`; at cap → `next_at ≈ now + cap_days`; `record_success` → `attempts=0`, `next_at=nil`. Assert `save_fields` persists (reload the model). |
| B5 eligibility filter | Tryout on `FaviconBackfillJob.eligible?`: matrix — `favicon_fetched=true`→false; `favicon_source='user_upload'`→false; `attempts>=max`→false; fresh `PROCESSING`→false; stale `PROCESSING` (completed_at old)→true; `next_at` future→false; `next_at` past/nil→true. Stub `Publisher.enqueue_favicon_fetch`, assert enqueue count over a fixture set. |
| B5 config resolution | Per MEMORY note (config test-mode merge trap): load defaults with `Onetime::Config.load(defaults_path)` (skips test merge) to assert `jobs.favicon_backfill` defaults resolve; verify `enabled?` requires BOTH gates. |

Note the boot trap (MEMORY): single-file tryouts need CI secrets exported or `boot true` locally, else "Key version cannot be nil."

**Frontend — vitest / component tests:**

| Behavior | Test |
|---|---|
| F1 store action | Mock `$api.post`; assert `refreshFavicon('abc')` POSTs `/api/domains/abc/icon/refresh`. |
| F2 composable | Assert `refreshFavicon` resolves extid, calls store, toasts success; on store rejection `wrap` swallows + error-toasts. |
| F3 UI | `SimpleBrandPanel` renders the button; click → `onRefreshFavicon` fires; button disabled/explained when icon `favicon_source==='user_upload'`. |

**Integration (optional, full-mode rack spec):** `POST /api/domains/:extid/icon/refresh` with a session → 200 + queued; unauthenticated → 401; unentitled → 403.

---

## 5. Open decisions for the human

Genuinely ambiguous — each needs a call before or during build:

1. **Backoff schedule numbers (b).** No existing validation backoff to mirror (`domain_refresh_job` re-checks every domain every 30m with zero skip; `vhost_fetch_failed_at` is written-never-read; `MailerConfig#check_recent?` is dead code). Blueprint proposes `base_days=1`, `×2`, `cap_days=30`, `max_attempts=6` (offsets 1/2/4/8/16/30d then permanent stop). Confirm the cap and whether a permanently-failed domain should ever be auto re-probed, or only via the Phase 2 `force: true` manual button.

2. **Should enqueue-on-add fire at all given the domain is unverified? (a)** At add time the domain is `:unverified` (`custom_domain.rb:648`) and DNS may not point at OTS. `FetchDomainFavicon` hits `https://<display_domain>/favicon.ico` on the **public** host, so it can succeed if the customer's site already serves a favicon, or no-op/timeout otherwise. Options: (i) enqueue on add as specified (double-fires with verify, guard makes it idempotent), (ii) rely solely on the verify-transition enqueue and drop add-time. Task specifies add-time; confirm you don't want to defer to verify-only.

3. **Manual-refresh feature-flag gate (Phase 2 backend).** Gate `RefreshDomainFavicon` on `jobs.favicon_fetch.enabled` (dead button when off, consistent with `verify_domain.rb:351`) vs always-run (inline synchronous DNS+HTTPS fetch on the request thread when jobs disabled, `publisher.rb:362-368`). Recommendation: gate it.

4. **UI button placement/shape (Phase 2 frontend).** Bare "Refresh favicon from domain" button in `SimpleBrandPanel.vue` (minimal) vs full `BrandFaviconField.vue` with an icon thumbnail (requires loading `iconImage` into `useBranding` — only `logoImage` is loaded today). Recommendation: start with the bare button; thumbnail is a follow-up.

5. **Backfill coverage per run (d).** A single nightly run scans only the newest `batch_size` domains (`instances.revrangeraw(0, batch_size-1)`). For a population larger than `batch_size`, decide: large enough `batch_size` (blueprint default 500), or a persisted cursor/offset paginating across nights.

6. **Retry-of-"none-found" policy (b/d).** `record_none_found` ends at `COMPLETED + favicon_fetched=false` — a site that genuinely has no favicon. The proposed filter re-probes these on the backoff schedule (they may add a favicon later). Confirm you want to retry "none found" at all, or treat none-found as terminal (only `FAILED` retried).

7. **Does `FaviconBackfillJob.enabled?` require the worker flag? (d)** If `jobs.favicon_fetch.enabled` is off, the worker consumes+acks (drops) enqueued messages, so backfill would be pure waste. Blueprint gates on BOTH flags. Confirm, or make the backfill flag independent and document the dependency.

**Relevant files (absolute paths):**
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/lib/onetime/jobs/publisher.rb`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/apps/api/domains/logic/domains/add_domain.rb`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/apps/api/domains/logic/domains/remove_domain_image.rb` (mirror for new logic class)
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/apps/api/domains/routes.txt`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/apps/api/domains/logic/domains.rb`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/lib/onetime/operations/fetch_domain_favicon.rb`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/lib/onetime/operations/verify_domain.rb`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/lib/onetime/models/custom_domain.rb`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/lib/onetime/jobs/scheduled/domain_refresh_job.rb` (template)
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/lib/onetime/jobs/scheduled/favicon_backfill_job.rb` (NEW)
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/etc/defaults/config.defaults.yaml`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/src/shared/stores/domainsStore.ts`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/src/shared/composables/useBranding.ts`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/src/apps/workspace/domains/DomainBrand.vue`
- `/Users/d/Projects/dev/onetimesecret/worktrees/onetimesecret/witty-summit/onetimesecret/src/apps/workspace/components/dashboard/brand/SimpleBrandPanel.vue`
