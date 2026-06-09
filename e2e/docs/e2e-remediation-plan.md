# E2E Test Suite Remediation Plan

> Status: **Proposed** · Created: 2026-06-09 · Owner: TBD
>
> Motivation: The `container-e2e-tests` check has been a chronic source of red
> CI and perceived flakiness (e.g. PR #3399). This document itemizes the root
> causes and lays out a phased, best-practice remediation so the suite becomes
> trustworthy, fast, and maintainable. **We have no room for flaky tests.**

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

**Acceptance:** `container-e2e-tests` green on #3399; new Ruby spec covers both
branches.

---

## Phase 1 — Stop the bleeding (mechanical, high-leverage)

1. **Fix reporter/artifacts.** Make `e2e/playwright.config.ts` reporters
   environment-aware (CI: `list`, `github`, `html`, `json`, `blob`); drop the
   hard-coded `--reporter` overrides in `package.json` and `.github/workflows/e2e.yml`;
   upload both `e2e/playwright-report/` and `e2e/test-results/` with `if: always()`.
2. **Lint-ban flaky primitives.** Add `eslint-plugin-playwright` to
   `eslint.config.ts` for `e2e/**`; `no-restricted-syntax` forbidding
   `waitForLoadState('networkidle')` and `page.waitForTimeout(...)`. Roll out
   `warn` → directory sweeps → `error`.
3. **Make flake blocking.** Keep `retries: 2` for traces, add a CI step parsing
   `results.json` that fails the job on any `flaky` outcome. Add
   `e2e/QUARANTINE.md` for `test.fixme`'d tests with owner + issue link.

---

## Phase 2 — Make coverage real

1. **Auth via global-setup + `storageState`.** `e2e/global.setup.ts` (setup
   project) registers a test user via `/signup` (fallback: `docker exec`
   `Onetime::Customer.create!`), logs in, saves `e2e/.auth/user.json`. Config
   adds `setup` project; `full`/`full-billing` get `dependencies: ['setup']` +
   `storageState`. Workflow seeds `TEST_USER_*` and runs `e2e/all e2e/full`.
2. **Deterministic app-readiness signal.** Frontend sets
   `document.documentElement.dataset.appReady = 'true'` after mount + brand
   theme applied; tests wait on that, replacing `__BOOTSTRAP_ME__` polling +
   `networkidle`. *(Highest-leverage flake fix.)*
3. **Sweep `networkidle` → web-first assertions** (300 sites), per directory.
4. **Convert the 143 defensive skips**: (a) guaranteed precondition → run it;
   (b) genuinely optional feature → tagged project, not runtime self-skip;
   (c) unimplemented → `test.fixme` + issue link.

---

## Phase 3 — Structure & speed

1. **`e2e/fixtures.ts`**: `authedPage`, auto-collecting `consoleErrors` fixture
   (single maintained ignore-list), `gotoReady(path)` helper.
2. **Pin a known brand config** in `e2e.yml` (`BRAND_PRIMARY_COLOR=#3B82F6`);
   upgrade the mask-icon test to strict equality.
3. **Parallelize + shard**: once tests own their data, `fullyParallel: true`,
   raise `workers`, add a CI shard matrix merging `blob` reports.

---

## Suggested PR sequence

| PR | Phase | Scope | Risk |
|----|-------|-------|------|
| 1 | 0 | mask-icon conditional render + test + Ruby spec | Low — unblocks #3399 |
| 2 | 1 | reporter/artifacts, lint rules (warn), flaky gate | Low |
| 3 | 2.1+2.2 | global-setup/auth fixture + app-readiness signal | Med — surfaces real `full/` failures (intended) |
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
