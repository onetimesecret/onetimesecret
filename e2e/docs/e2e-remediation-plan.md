# E2E Test Suite Remediation Plan

> Status: **In progress.** Phases 0–2 have landed on `main`
> ([#3409](https://github.com/onetimesecret/onetimesecret/pull/3409),
> [#3411](https://github.com/onetimesecret/onetimesecret/pull/3411),
> [#3412](https://github.com/onetimesecret/onetimesecret/pull/3412),
> [#3416](https://github.com/onetimesecret/onetimesecret/pull/3416),
> [#3425](https://github.com/onetimesecret/onetimesecret/pull/3425)).
> Branch `chore/fix-e2e-consistency` makes `e2e/full/` a blocking CI lane.
> **Next up: Phase 3 fixtures for the suites that are still gated.**
> Created: 2026-06-09 · Last updated: 2026-09-27 · Owner: delano
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
| Phase 0 / PR 1 — unblock #3399 mask-icon + this plan | ✅ **Done** | [PR #3409](https://github.com/onetimesecret/onetimesecret/pull/3409) |
| Phase 1 / PR 2 — reporter/artifacts + lint-ban + flaky gate | ✅ **Done** | [PR #3411](https://github.com/onetimesecret/onetimesecret/pull/3411) |
| Phase 2.1+2.2 / PR 3 — auth setup project + app-readiness signal | ✅ **Done** | [PR #3412](https://github.com/onetimesecret/onetimesecret/pull/3412) |
| Phase 2.3 / PR 4 — `networkidle`/sleep sweep + lint→error | ✅ **Done** | [PR #3416](https://github.com/onetimesecret/onetimesecret/pull/3416) |
| Phase 2.4 / PR 5 — defensive-skip triage | ✅ **Done** | [PR #3425](https://github.com/onetimesecret/onetimesecret/pull/3425) (env gates, `test.fixme` quarantine); the org-existence conversions it deferred are done on `chore/fix-e2e-consistency` |
| Blocking full lane — `e2e/full/` in full auth mode | 🔄 **On branch** | `chore/fix-e2e-consistency`: two blocking matrix lanes, `e2e/full/` green locally against the full-lane image, every remaining skip tracked in [`QUARANTINE.md`](../QUARANTINE.md) |
| Phase 3 / PR 6 — fixtures for the gated suites, pinned config, parallel/shard | ⬜ Todo | see "Next: Phase 3" below |

> **CI-signal caveat for stacked PRs:** `container-e2e-tests` only triggers on
> PRs that target `develop`, `main`, or `rel/*` (the `pull_request.branches`
> filter in `.github/workflows/e2e.yml`). A PR stacked on a feature branch gets
> **no E2E run of its own**. Base each slice on `develop` (or the release
> branch) so it is exercised by the very workflow it modifies.

### Current state (2026-09-27, branch `chore/fix-e2e-consistency`)

**CI.** `.github/workflows/e2e.yml` builds the production image and runs it as
a matrix of two lanes, each on its own runner with its own Valkey container:

| Lane (check name) | Server | Suite | Tests |
|-------------------|--------|-------|-------|
| `container-e2e-tests (simple)` | `AUTHENTICATION_MODE=simple` | `e2e/all/` | 71 |
| `container-e2e-tests (full)` | `AUTHENTICATION_MODE=full`, SQLite authdb, `AUTH_VERIFY_ACCOUNT_ENABLED=false`, `CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false`, `ENABLE_ORGS=true` | `e2e/full/` + `setup` | 304 + 1 |

Both lanes are blocking and both run the flaky gate (a retry-only pass fails
the lane). `notify-results` fails unless both lanes pass. There is no
informational or `continue-on-error` step any more: the one that ran
`e2e/full/` non-blocking (5b0d3c5eab) is gone.

**What the full lane covers.** A local run of `e2e/full/` against the
full-lane image (podman, same env as the lane) passes 167 tests (plus
`setup`) and skips 137, with 0 failures and 0 flaky, in about 2.9 minutes on
one worker. The 167 are the signed-in workspace: settings layout,
organization settings and members, invitations and invite-token security
(including the invite signup, accept and decline journeys),
identifier URLs, the workspace switcher (`scope-switcher`,
`org-switcher-navigation`), the two no-custom-domain domain-context tests and
the full-mode accessibility scans. The lane account (`e2e/global.setup.ts`) owns one solo
default workspace; tests that need more people or a second workspace build
throwaway accounts through the product's own signup, invitation and
organization APIs (`e2e/support/members.ts`, `e2e/support/workspaces.ts`),
so none of them needs a seeded fixture. A pending invitation is sent through
the owner's Members tab and its token read back from the invitations API, so
the invite journeys need no mail.

**What remains gated, and why.** The 137 skips are all tracked in
[`QUARANTINE.md`](../QUARANTINE.md):

| Why it cannot run in the full lane | Tests | How it is marked | Issue |
|------------------------------------|------:|------------------|-------|
| Needs a custom domain on the test account | 55 | env gate `E2E_CUSTOM_DOMAINS` (five domain suites, five identifier-URL tests) | #3420 |
| Needs a custom domain and org SSO | 32 | env gates `E2E_CUSTOM_DOMAINS` + `E2E_SSO_UI` (the two domain SSO suites) | #3420 |
| Needs a custom domain (scope-switcher domain cases) | 12 | `test.fixme` unless `E2E_CUSTOM_DOMAINS` | #3420 |
| Needs two organizations with custom domains | 15 | `test.fixme` (cross-org isolation, domains-store cache, TC-SS-009/-054) | #3420 |
| Needs a custom domain; unimplemented | 7 | `test.fixme` (domain-context-consultant placeholders) | #3420 |
| Needs org SSO, or an account without `manage_sso` | 2 | `test.fixme` (ORG-DETAIL-006 unless `E2E_SSO_UI`, TC-DSSO-019) | #3420 |
| Needs a mail interceptor or an IdP | 3 | `test.fixme` (invite-flow-states INV-002, -003; org-invitation-flow INV-012) | #3421 |
| Needs an MFA-enrolled account | 11 | env gate `TEST_MFA_*` (10), `test.fixme` (invite-flow-states INV-005) | #3421 |
| **Total** | **137** | 97 env-gated, 40 `test.fixme` | |

No runtime `test.skip` on a DOM probe is left in `e2e/full/`: inside the env
gates, a missing domain, form, toggle or SSO tab now fails the test instead
of skipping it. Those gated suites have never run in any lane, so the first
configured run will need fixes.

### Next: Phase 3 — incremental fixtures for the gated suites

Add one fixture at a time, each with a lane (or a lane option) that sets its
flag, and remove the matching `QUARANTINE.md` rows in the same PR:

1. **Custom domains (#3420).** Boot the full lane with `DOMAINS_ENABLED=true`
   and give the lane account a custom domain before the suite runs (the
   validation strategy must accept a domain with no real DNS), then set
   `E2E_CUSTOM_DOMAINS` to its name. Unlocks the domain suites, the
   identifier-URL domain tests and the scope-switcher domain cases (67
   tests). Expect to fix the suites themselves: they have never run.
   Turning domains on also changes what the signed-in pages render (the
   domain switcher appears), so regenerate the full a11y baseline.
2. **Two organizations with custom domains (#3420).** Extend the two-workspace
   owner in `e2e/support/workspaces.ts` with a custom domain per workspace,
   then lift `cross-org-domain-isolation`, `domains-store-org-cache` and
   TC-SS-009/-054. Their DOM scrapers need a rewrite against the current UI.
3. **Org SSO (#3420).** A lane option with `ORGS_SSO_ENABLED=true` and
   `E2E_SSO_UI`; the per-domain SSO suites also need a custom domain (step 1)
   and, for six cases, two.
4. **Invitation mail (#3421).** A Mailpit sidecar and `EMAILER_MODE=smtp`, as
   `e2e-full-auth.yml` already runs, for the magic-link invite (INV-002 in
   `invite-flow-states`) and Gmail alias matching (INV-012, which also needs
   real Gmail addresses). The SSO invite (INV-003) also needs an IdP.
5. **MFA (#3421).** Turn MFA on in the full lane (`AUTH_MFA_ENABLED`; the
   lane's bootstrap reports `mfa: false` today), enroll a throwaway account in
   TOTP during the run (`e2e/support/totp.ts` derives the codes, as
   `e2e/auth/session-consistency.spec.ts` does) and point `TEST_MFA_*` at it,
   for `mfa-bootstrap-reactivity` and INV-005 in `invite-flow-states`.

The rest of Phase 3 is unchanged: a shared `e2e/fixtures.ts`, more pinned
config, then parallel workers and sharding once tests own their data.

## Headline finding

_As found on 2026-06-09. "Current state" above has where things stand now._

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

### Invitation/`full/` suites: test-side defect classes already corrected

Switching `full/` on (Phase 2.1+2.2) unmasked a stack of **test-side** defects in
the invitation suites — corrected across successive rounds (#3448, #3490, and the
`#SLEXY5` series). Catalogued here so a re-failure is matched against a known class
before it is mistaken for a product regression. What remains *after* these are the
fixture-dependent cases in [`QUARANTINE.md`](../QUARANTINE.md) (#3419/#3421) — those
are a **coverage gap that never ran in CI, not a regression**.

| Class | Fixed in | What was wrong |
|-------|----------|----------------|
| A · storageState session leakage | `9148f41`, `335d6c3` | `full`/`newContext()` inherit the owner session; the auth guard redirects authenticated visitors off `/signin`, so "anonymous" flows never saw the form. Fix: `clearCookies()` / explicit empty `storageState`. |
| B · strict-mode / ambiguous locators | `dd038eb`, `9148f41`, `5ac72c6`, #3490 | Generic CSS (`.rounded-md`) matched ancestor+leaf+~60 rows; broad `getByText`/`getByRole`/`getByLabel` matched many/zero. Fix: stable `data-testid` (`org-invitation-row`), `.first()` scoping, test IDs over CSS/role. |
| C · wrong API endpoint paths | `033fe95`, `335d6c3` | Non-existent routes (`/api/v2/org/:extid/invitations`, `/api/v2/bootstrap/authenticated`) → real ones (`/api/organizations/:extid/invitations`, `/bootstrap/me`). |
| D · response-shape / vacuous assertions | `033fe95`, `335d6c3` | Checked `data.message` vs `FormError.to_h` `{error}` (ADR-013); read `record.email` from a 404 body; invited email is a readonly input (`toHaveValue`). |
| E · signin form-variant coupling | `033fe95`, `335d6c3`, `00ef816` | Specs assumed a password-*tab* variant; CI serves password-only. Fix: dual-variant `loginUser` from `global.setup.ts`. |
| F · wrong flow model (signup not atomic) | `335d6c3` | Signup establishes a session, *then* the state machine shows `direct_accept` confirmed via an explicit Accept button. INV-001/SEC-INV-003 rewritten to that flow. |
| G · decline-control state dependence | `9148f41`, `5ac72c6` | Unauthenticated invitee lands in `signup_required`/`signin_required` where decline is `invite-signup-decline`/`invite-signin-decline`, not `decline-invitation-btn`. |
| H · flaky waits | Phase 1 + 2.3 | `networkidle`/`waitForTimeout` → app-readiness signal + web-first assertions. |

> **Resolved latent helpers:** the per-spec `getFirstOrganization` copies are
> one helper in `e2e/support/organizations.ts` that waits for the org list,
> and the five `getFirstDomain` copies in the `domain-*` specs are one helper
> in `e2e/support/domains.ts` that waits for the domain table (the copies took
> the panel's "Add Domain" link as the first domain). The domain helper has
> not run yet: no lane provides a custom domain.

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
   `e2e/global.setup.ts` (setup project) registers a test user via `/signup`,
   logs in, saves `e2e/.auth/user.json`. The new account must be able to sign
   in without verifying email: simple mode gets that from
   `AUTH_AUTOVERIFY=true`, full mode from `AUTH_VERIFY_ACCOUNT_ENABLED=false`.
   Config adds `setup` project; `full`/`full-billing` get
   `dependencies: ['setup']` + `storageState`. The workflow seeds ephemeral
   `TEST_USER_*`; today the full lane runs `e2e/full/` in full auth mode (see
   "Current state" above).
2. ✅ **Deterministic app-readiness signal** ([#3412](https://github.com/onetimesecret/onetimesecret/pull/3412), signal half).
   Frontend sets `document.documentElement.dataset.appReady = 'true'` in
   `src/main.ts` after mount + brand theme application + `router.isReady()`;
   the setup/auth path waits on it. The other half — migrating *specs* off
   `__BOOTSTRAP_ME__` polling + `networkidle` onto the flag — lands with the
   PR 4 sweep. *(Highest-leverage flake fix.)*
3. ✅ **Sweep `networkidle` → web-first assertions** (PR 4, branch
   `claude/e2e-phase24-networkidle-sweep`). All 341 flagged call sites (298
   `networkidle` + 43 `waitForTimeout`) replaced per directory with the
   readiness flag, `waitForURL`/web-first URL assertions for in-SPA
   navigations, `expect.poll`/`waitForResponse` for capture flags and API
   round-trips; both lint rules now `'error'`. `__BOOTSTRAP_ME__`
   readiness-polling is gone (content reads remain, deliberately).
4. ✅ **Convert the 143 defensive skips**: (a) guaranteed precondition → run it;
   (b) genuinely optional feature → tagged project, not runtime self-skip;
   (c) unimplemented → `test.fixme` + issue link. Done in #3425 and on
   `chore/fix-e2e-consistency`; what is left is listed in `QUARANTINE.md`.

---

## Phase 3 — Structure & speed

0. **Fixtures for the gated suites**, one per PR: see "Next: Phase 3" in the
   Progress section.
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
| 2 | 1 | reporter/artifacts, lint rules (warn), flaky gate | ✅ Done ([#3411](https://github.com/onetimesecret/onetimesecret/pull/3411)) |
| 3 | 2.1+2.2 | global-setup/auth fixture + app-readiness signal | ✅ Done ([#3412](https://github.com/onetimesecret/onetimesecret/pull/3412)) |
| 4 | 2.3 | `networkidle`/sleep sweep, by directory; lint → error | ✅ Done ([#3416](https://github.com/onetimesecret/onetimesecret/pull/3416)) |
| 5 | 2.4 | defensive-skip triage — revive `incoming-secrets`, env gates, `fixme` fixture-dependent suites | ✅ Done ([#3425](https://github.com/onetimesecret/onetimesecret/pull/3425)); the deferred org-existence conversions are done on `chore/fix-e2e-consistency` |
| — | 2 | blocking `full` lane: `e2e/full/` in full auth mode, green, remaining skips tracked | 🔄 On branch `chore/fix-e2e-consistency` |
| 6 | 3 | fixtures for the gated suites (domains, multi-org, SSO, mail, MFA), fixtures.ts, pinned config, parallel/shard | Todo; one fixture per PR |

## Key risks & mitigations

- **Turning on `full/` will reveal genuine bugs** previously masked by skips —
  that is the goal; budget for fixes, land behind the flaky gate.
- **Auth seeding** assumes `/signup` is enabled in the container; if closed,
  seed via `docker exec ... Onetime::Customer.create!`.
- **Mass lint flip** staged `warn` → sweep → `error` to keep diffs reviewable.

## Acceptance criteria (end state)

- Green CI with **0 skipped-by-default** tests in `all/`.
- `full/` + `full-billing/` execute in CI against a seeded session. (`full/` does,
  in the blocking full lane; `full-billing/` still needs a billing-enabled lane.)
- **No** `networkidle` / `waitForTimeout` in the suite (lint-enforced).
- A retry-only pass turns CI **red**; HTML + trace artifacts always uploaded.
