# E2E Test Suite Remediation Plan

> Status: **In progress** — Phase 0 complete ([PR #3409](https://github.com/onetimesecret/onetimesecret/pull/3409)); Phase 1 / PR 2 in review ([PR #3411](https://github.com/onetimesecret/onetimesecret/pull/3411)); Phase 2.1+2.2 / PR 3 in review ([PR #3412](https://github.com/onetimesecret/onetimesecret/pull/3412)); **next up: PR 4 / Phase 2.3.**
> Created: 2026-06-09 · Last updated: 2026-06-09 · Owner: TBD
>
> Motivation: The `container-e2e-tests` check has been a chronic source of red
> CI and perceived flakiness (e.g. PR #3399). This document itemizes the root
> causes and lays out a phased, best-practice remediation so the suite becomes
> trustworthy, fast, and maintainable. **We have no room for flaky tests.**
>
> **This is a living tracker.** Update the Progress section and the PR-sequence
> table as each slice lands.

## Progress & how to continue

| Phase / PR | Status | Where |
|------------|--------|-------|
| Phase 0 / PR 1 — unblock #3399 mask-icon + this plan | ✅ **Done** | [PR #3409](https://github.com/onetimesecret/onetimesecret/pull/3409) · branch `claude/sleepy-shannon-21ko6k` |
| Phase 1 / PR 2 — reporter/artifacts + lint-ban + flaky gate | 🔄 **In review** | [PR #3411](https://github.com/onetimesecret/onetimesecret/pull/3411) · branch `claude/affectionate-clarke-4fyakw` |
| Phase 2.1+2.2 / PR 3 — auth setup project + app-readiness signal | 🔄 **In review** | [PR #3412](https://github.com/onetimesecret/onetimesecret/pull/3412) · branch `claude/e2e-phase2-auth-readiness` (stacked on #3411) |
| Phase 2.3–2.4 / PRs 4–5 — `networkidle` sweep + lint→error, skip triage | ⏭️ **Next** | not started |
| Phase 3 / PR 6 — fixtures module, pinned config, parallel/shard | ⬜ Todo | not started |

> **CI-signal caveat for stacked PRs:** `container-e2e-tests` only triggers on
> PRs that target `develop`, `main`, or `rel/*` (the `pull_request.branches`
> filter in `.github/workflows/e2e.yml`). A PR stacked on a feature branch gets
> **no E2E run of its own** — PR 1 (based on #3399's branch) only saw its
> green/red signal one hop downstream, on #3399's checks. PR 2 was branched
> from the stack, but #3399/#3409 merged to `develop` while it was in flight,
> so it targets `develop` directly and gets a real run. Keep it that way for
> PR 3 onward: base on `develop` so each phase is exercised by the very
> workflow it modifies.

### For a fresh contributor picking up PR 4 (Phase 2.3: `networkidle`/sleep sweep, lint → error)

1. **Verify Phases 0–2.2 already landed — do not redo them.** Phase 1:
   `pnpm lint:e2e` runs (341 warnings, 0 errors), `.github/workflows/e2e.yml`
   has a "Fail on flaky tests" step. Phase 2.1+2.2: `e2e/global.setup.ts`
   exists, `e2e/playwright.config.ts` has `setup`/`chromium`/`full`/
   `full-billing` projects, and `src/main.ts` sets
   `html[data-app-ready="true"]`. If any of that is missing, see
   [PR #3411](https://github.com/onetimesecret/onetimesecret/pull/3411) /
   [PR #3412](https://github.com/onetimesecret/onetimesecret/pull/3412).
2. **Where to branch PR 4.** If #3412 has merged, branch off `develop`.
   Otherwise stack on `claude/e2e-phase2-auth-readiness` — PR 4 sweeps the
   spec files and flips the lint rules, and needs PR 3's readiness signal to
   sweep *to*. Either way the PR must **target `develop`** (see the CI-signal
   caveat above).
3. **Concrete starting points** (verified against the tree as of PR 3):
   - The lint baseline is **341 warnings, 0 errors** from `pnpm lint:e2e`:
     298 `playwright/no-networkidle` + 43 `playwright/no-wait-for-timeout`.
     By directory: `all/` 29, `auth/` 16, `full/` 262, `full-billing/` 34.
     Sweep **per directory** (one reviewable commit each); flip both rules
     from `'warn'` to `'error'` at `eslint.config.ts:606-607` in the final
     commit, once the count is 0. Don't use `--quiet` to check progress — it
     skips *executing* warn-level rules; `pnpm lint:e2e` shows them.
   - The replacement primitive: wait on the app-readiness flag with a
     web-first assertion —
     `await expect(page.locator('html[data-app-ready="true"]')).toBeAttached()`.
     Canonical usage: `e2e/global.setup.ts:53`. The flag is set in
     `src/main.ts:47` after mount + brand theme + `router.isReady()`. For
     waits that aren't "is the app up" (element state, URL changes), use
     ordinary web-first assertions / `waitForURL` instead.
   - 9 spec files also read or poll `window.__BOOTSTRAP_ME__` — some via
     `waitForFunction` (e.g. `e2e/all/integration.spec.ts:307`), some via
     `page.evaluate` reads (e.g. `e2e/auth/sso-csrf.spec.ts:47`); list them
     with `grep -rl __BOOTSTRAP_ME__ e2e/all e2e/auth e2e/full`. Replace the
     *readiness-polling* uses with the readiness flag while you're in each
     file — that is explicitly Phase 2.2's "tests wait on that" half. (Reads
     that inspect bootstrap *content*, like the sso-csrf shrimp checks, are
     fine to keep.)
   - Known interaction in `full/`: every spec still runs a manual
     `loginUser(page)` helper (pattern at
     `e2e/full/cross-org-domain-isolation.spec.ts:55-78`) even though the
     `full` project now starts authenticated via `storageState`. When
     sweeping `full/`, expect those helpers to be dead weight or actively
     broken (an authed user visiting `/signin` gets redirected) — deleting
     the call sites is in scope where it unblocks the sweep; broader spec
     triage (the 143 defensive skips) stays PR 5.
   - Check CI state of #3412 first: the first `full/` runs are *expected* red
     (previously-masked failures). Quarantine via `e2e/QUARANTINE.md`
     (`test.fixme` + owner + issue link) rather than re-skipping; the flaky
     gate stays blocking.
4. **Definition of done for PR 4:** `pnpm lint:e2e` reports **0 problems**
   with both rules at `'error'`; no `networkidle` / `waitForTimeout` /
   `__BOOTSTRAP_ME__`-polling call sites remain in `e2e/`; suite passes (or
   failures are quarantined with issue links), and no test regresses to
   pass-only-on-retry (the flaky gate enforces this).
5. **Hand off before you open the PR.** This doc is the tracker — leave it the
   way you found it: set your row in the Progress table and the PR-sequence
   table (status + PR link), update the status line at the top, and **rewrite
   this section for PR 5** (defensive-skip triage, Phase 2.4) with verified
   file/line starting points (don't guess — confirm them against your final
   tree the way the pointers above were). A stale pickup section costs the
   next contributor their first hour.

## Headline finding

The failures are **not** primarily random flake. The recurring red on
brand/TOTP branches is a **deterministic test/behavior contradiction** sitting on
top of a genuinely fragile suite. The systemic fragility (300 `networkidle`
waits, 143 self-skipping tests, a 23-file `full/` suite that never runs in CI)
is what earns it the "chronically failing" reputation.

## Guiding principles

1. **A test must be able to fail.** Anything that can only pass-or-skip is
   deleted or made deterministic.
2. **No timing guesses.** Replace `networkidle` / `waitForTimeout` with
   web-first assertions and an explicit app-readiness signal.
3. **Flake is blocking, not silent.** Retries stay as a trace-gathering net, but
   a "passed-only-on-retry" result turns CI red.
4. **One correct pattern, in one place.** Shared fixtures, not 29
   re-implementations.
5. **Land it in reviewable slices.** No single 343-file diff.

---

## Itemized problems (evidence)

Gathered across 29 spec files / 412 `test()` blocks.

### The immediate hard failure

`e2e/all/brand-customization.spec.ts:337 › link mask-icon color attribute
carries a valid hex color` — `Received: ""`.

- Template renders `color="{{brand_primary_color}}"`
  (`apps/web/core/templates/partials/head-base.rue:20`).
- `brand_primary_color = brand_config['primary_color']` with **no fallback**
  (`apps/web/core/views/helpers/initialize_view_vars.rb:192`).
- Commits `6d26430` ("Stop backfilling brand_primary_color default at
  serialization time") and `e621290` deliberately removed the default so the
  frontend can fall through to `NEUTRAL_BRAND_DEFAULTS`.
- The CI E2E container runs **unbranded** (no `BRAND_*` env), so the attribute
  renders as `color=""` — but the test asserts it is *always* a valid hex.

This fails 100% of the time on any branch carrying the "stop backfilling"
change without brand config; it is deterministic, not random.

### Systemic problems

| # | Problem | Evidence | Why it hurts |
|---|---------|----------|--------------|
| 1 | `networkidle` everywhere | **300** `waitForLoadState('networkidle')` | Officially discouraged by Playwright; races SPA hydration → #1 flake source. |
| 2 | Hard-coded sleeps | **43** `waitForTimeout()` | Arbitrary sleeps either flake (too short) or waste time (too long). |
| 3 | "Defensive skip" tests that can't fail | **143** `test.skip(true, 'route/form not available')` | Zero signal; reports green. 19 of 48 CI tests skip this way — false confidence. |
| 4 | A whole suite that never runs in CI | `full/` (19) + `full-billing/` (4) gated by **127** `test.skip(!hasCredentials)`; CI only runs `e2e/all/` and passes no creds | Hundreds of tests look like coverage but execute *never*. No auth fixture exists. |
| 5 | Broken artifact pipeline | Workflow `--reporter=github` overrides config `html` reporter → "No files were found ... playwright-report/" | No HTML report / trace artifact on failure → slow repeated re-runs. |
| 6 | Retries silently mask flake | `retries: 2` + `--max-failures=5`, no flaky gate | Flaky tests green-washed on retry with no tracking/quarantine. |
| 7 | No shared fixtures | No `e2e/*.ts` helper module; every spec re-implements login/nav/waits | Fixes must be applied 29× and drift. |
| 8 | Environment coupling | Brand tests assert against "whatever the default container serves" | Behavior changes (#3381) silently break tests; no known brand state pinned. |
| 9 | Serial + slow | `workers: 1`, `fullyParallel: false` → 2.8 min for 28 tests | One hung test blocks all; slow feedback discourages local runs. |

---

## Phase 0 — Unblock CI (the mask-icon failure)

**Direction: conditional render + test asserts "if present, valid hex".**

1. **`apps/web/core/views/helpers/initialize_view_vars.rb`** (~line 192): add an
   explicit boolean rather than relying on template-engine truthiness:
   ```ruby
   brand_primary_color = brand_config['primary_color']
   has_brand_color     = !brand_primary_color.to_s.strip.empty?
   ```
   Add `'has_brand_color' => has_brand_color,` to the returned view-vars hash
   (near line 242).
2. **`apps/web/core/views/base.rb`** (`render`, ~line 123): add
   `'has_brand_color' => view_vars['has_brand_color'],` to `template_vars` so the
   template context can see it.
3. **`apps/web/core/templates/partials/head-base.rue`** (lines 20–22): only emit
   brand-colored tags when a color exists (no empty `color=""` / `content=""`):
   ```handlebars
   {{#if has_brand_color}}
     <link nonce="{{app.nonce}}" rel="mask-icon" href="/safari-pinned-tab.svg" color="{{brand_primary_color}}">
     <meta name="theme-color" content="{{brand_primary_color}}" media="(prefers-color-scheme: light)">
   {{/if}}
   <meta name="theme-color" content="#1a1a1a" media="(prefers-color-scheme: dark)">
   ```
4. **`e2e/all/brand-customization.spec.ts:337`**: assert reality — absent is
   valid, present must be hex.
5. **Backend regression spec**: unbranded → no `mask-icon` tag; branded → tag
   present with exact value. Locks the contract.
6. **Pin a deterministic brand color in CI** (`.github/workflows/e2e.yml`): run
   the container with `-e BRAND_PRIMARY_COLOR='#3B82F6'` (the neutral default,
   `#3049`). This makes the head-base assertion deterministic so the E2E test can
   require the tag's presence and assert its exact color **without a defensive
   skip** — the test fails on any template→config regression rather than silently
   skipping. (Pulled forward from Phase 3 so PR 1 exemplifies "a test must be able
   to fail" instead of introducing a new self-skip.)

**Acceptance:** `container-e2e-tests` green on #3399; new Ruby spec covers both
branches; the head-base E2E asserts an exact color with **no** `test.skip` and
**no** `networkidle`.

---

## Phase 1 — Stop the bleeding (mechanical, high-leverage)

> **Concrete starting points** (verified against the tree as of Phase 0):
> - The reporter override that breaks the HTML report lives in **two** places that
>   both override the `reporter` array in `e2e/playwright.config.ts:38`: the
>   `package.json` `test:playwright` script (`--reporter=list`) and the
>   `.github/workflows/e2e.yml` "Run Playwright E2E tests" step (`--reporter=github`).
>   Net effect today: `playwright-report/` is never produced, so the upload step
>   logs "No files were found with the provided path: e2e/playwright-report/".
> - The `e2e.yml` "Upload Playwright Report" step currently uploads only
>   `e2e/playwright-report/`; add `e2e/test-results/` (traces/videos/screenshots).
> - Lint config is the flat `eslint.config.ts` at repo root. It currently targets
>   `src/**` and does **not** lint `e2e/**` — add an `e2e/**` block.

1. **Fix reporter/artifacts.** Make `e2e/playwright.config.ts` reporters
   environment-aware (CI: `list`, `github`, `html`, `json`, `blob`); drop the
   hard-coded `--reporter` overrides in `package.json` and `.github/workflows/e2e.yml`;
   upload both `e2e/playwright-report/` and `e2e/test-results/` with `if: always()`.
2. **Lint-ban flaky primitives.** Add `eslint-plugin-playwright` to
   `eslint.config.ts` with an `e2e/**` block; `no-restricted-syntax` forbidding
   `waitForLoadState('networkidle')` and `page.waitForTimeout(...)`. Roll out
   `warn` → directory sweeps → `error` (there are ~300 `networkidle` + ~43
   `waitForTimeout` call-sites today, so do **not** flip to `error` in this PR).
3. **Make flake blocking.** Keep `retries: 2` for traces, add a CI step parsing
   the JSON reporter output that fails the job on any `flaky` outcome. Add
   `e2e/QUARANTINE.md` for `test.fixme`'d tests with owner + issue link.

**Acceptance:** HTML report + traces uploaded on failure; `networkidle` /
`waitForTimeout` lint rules active (at `warn`); a retry-only ("flaky") pass turns
CI **red**.

---

## Phase 2 — Make coverage real

1. ✅ **Auth via global-setup + `storageState`** ([#3412](https://github.com/onetimesecret/onetimesecret/pull/3412)).
   `e2e/global.setup.ts` (setup project) registers a test user via `/signup`
   (fallback: `docker exec` `Onetime::Customer.create!` — not needed; the CI
   container runs with `AUTH_AUTOVERIFY=true`), logs in, saves
   `e2e/.auth/user.json`. Config adds `setup` project; `full`/`full-billing`
   get `dependencies: ['setup']` + `storageState`. Workflow seeds ephemeral
   `TEST_USER_*` and runs `e2e/all/ e2e/full/`.
2. ✅ **Deterministic app-readiness signal** ([#3412](https://github.com/onetimesecret/onetimesecret/pull/3412), signal half).
   Frontend sets `document.documentElement.dataset.appReady = 'true'` in
   `src/main.ts` after mount + brand theme application + `router.isReady()`;
   the setup/auth path waits on it. The other half — migrating *specs* off
   `__BOOTSTRAP_ME__` polling + `networkidle` onto the flag — lands with the
   PR 4 sweep. *(Highest-leverage flake fix.)*
3. **Sweep `networkidle` → web-first assertions** (300 sites), per directory.
4. **Convert the 143 defensive skips**: (a) guaranteed precondition → run it;
   (b) genuinely optional feature → tagged project, not runtime self-skip;
   (c) unimplemented → `test.fixme` + issue link.

---

## Phase 3 — Structure & speed

1. **`e2e/fixtures.ts`**: `authedPage`, auto-collecting `consoleErrors` fixture
   (single maintained ignore-list), `gotoReady(path)` helper.
2. **Extend the pinned-config approach** beyond the brand color (done for
   `BRAND_PRIMARY_COLOR` in Phase 0) so every environment-coupled assertion tests
   a known, deterministic state rather than "whatever the default serves".
3. **Parallelize + shard**: once tests own their data, `fullyParallel: true`,
   raise `workers`, add a CI shard matrix merging `blob` reports.

---

## Suggested PR sequence

_Live status is tracked in the **Progress & how to continue** section near the top._

| PR | Phase | Scope | Risk / status |
|----|-------|-------|---------------|
| 1 | 0 | mask-icon conditional render + deterministic (skip-free) test + Ruby spec + CI brand-color pin | ✅ Done ([#3409](https://github.com/onetimesecret/onetimesecret/pull/3409)) — unblocks #3399 |
| 2 | 1 | reporter/artifacts, lint rules (warn), flaky gate | 🔄 In review ([#3411](https://github.com/onetimesecret/onetimesecret/pull/3411)) |
| 3 | 2.1+2.2 | global-setup/auth fixture + app-readiness signal | 🔄 In review ([#3412](https://github.com/onetimesecret/onetimesecret/pull/3412), stacked on #3411) — surfaces real `full/` failures (intended) |
| 4 | 2.3 | `networkidle`/sleep sweep, by directory; lint → error | Med — large but mechanical |
| 5 | 2.4 | defensive-skip triage | Med |
| 6 | 3 | fixtures.ts, pinned brand, parallel/shard | Low |

## Key risks & mitigations

- **Turning on `full/` will reveal genuine bugs** previously masked by skips —
  that is the goal; budget for fixes, land behind the flaky gate.
- **Auth seeding** assumes `/signup` is enabled in the container; if closed,
  seed via `docker exec ... Onetime::Customer.create!`.
- **Mass lint flip** staged `warn` → sweep → `error` to keep diffs reviewable.

## Acceptance criteria (end state)

- Green CI with **0 skipped-by-default** tests in `all/`.
- `full/` + `full-billing/` execute in CI against a seeded session.
- **No** `networkidle` / `waitForTimeout` in the suite (lint-enforced).
- A retry-only pass turns CI **red**; HTML + trace artifacts always uploaded.
