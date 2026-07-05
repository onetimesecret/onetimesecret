# Public Surfaces: Accessibility Audit

*Audit date: 2026-07-04. Scope: the six public (unauthenticated) web surfaces
of the app, scanned with axe-core 4.12 against WCAG 2.0/2.1 Level A + AA plus
axe best-practice rules, on a local production build.*

Companion to the accessibility
[`OVERVIEW.md`](../development/accessibility/OVERVIEW.md), which describes the
accessibility features and intent; this document records what an automated scan
actually found so gaps can be tracked and fixed.

> **Status (resolved on this branch):** every violation in sections 3–4 below
> has been fixed, and **dark mode** — a caveat in the original audit — was
> scanned and fixed too. All six public surfaces now report **zero** axe
> violations in both light and dark themes. The findings are retained below as
> the historical record; see [§7 Resolution & ongoing enforcement](#7-resolution--ongoing-enforcement)
> for what changed and how regressions are now prevented automatically.

## Method

| | |
|---|---|
| **Engine** | [axe-core](https://github.com/dequelabs/axe-core) 4.12.1 (Deque) — the same engine Lighthouse uses for its accessibility category, run directly for full violation detail |
| **Driver** | Playwright, headless Chromium |
| **Ruleset** | WCAG 2.0 / 2.1 **Level A + AA** (`wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`) plus axe **best-practice** |
| **Target** | Local production build (`RACK_ENV=production bin/ots server`) on `http://127.0.0.1:7143` |
| **Theme** | Light mode |
| **Procedure** | Each page loaded, allowed to fully mount (`html[data-app-ready="true"]`), then scanned against `document` |

Each surface returned HTTP 200 and mounted successfully before scanning.

## 1. Scope

Surfaces audited (the public routes that render a page; `/help`, `/icons`, and
`/about` return server-side 404s and were excluded):

- `/` — Home
- `/signin` — Sign In
- `/signup` — Create Account
- `/forgot` — Forgot Password
- `/pricing` — Pricing
- `/feedback` — Feedback

## 2. Summary

Four distinct violation rules across the six surfaces; no page was fully clean,
but nothing rose to blocker severity. The two **serious** issues are WCAG AA and
are mostly _global_ (shared header/footer), so a small number of fixes clear
them across every page.

| Surface | Violations (nodes) | Needs review | axe passes |
|---|---|---|---|
| Home | 2 (2) | 3 | 42 |
| Sign In | 3 (3) | 1 | 39 |
| Create Account | 3 (3) | 0 | 41 |
| Forgot Password | 2 (3) | 1 | 38 |
| Pricing | 2 (2) | 0 | 38 |
| Feedback | 2 (2) | 1 | 42 |

## 3. Findings

Severity is axe's impact rating (serious > moderate).

### F1 (serious): `color-contrast` — WCAG 2.1 AA (1.4.3) — all 6 pages

Text does not meet the 4.5:1 minimum contrast ratio for normal text.

- **Release-notes version link** (shared header/footer, present on every page):
  `#6a7282` on `#f3f4f6` = **4.39:1** (needs 4.5:1), 12px normal weight.
  Global — one change clears 6 nodes. Darken one step (e.g. `text-gray-600`
  → `text-gray-700`).
  ```html
  <a href="…/releases/tag/v0.0.0-rc0" aria-label="Release Notes"> v0.0.0-rc0 (…)</a>
  ```
- **"Send Reset Link" primary button** (`/forgot`): white `#ffffff` on
  `#3b82f6` (`bg-brand-500`) = **3.67:1** (needs 4.5:1), 16px bold. The primary
  brand button color fails AA for its label. Use `brand-600`/`brand-700` for
  the button background (or darken the brand primary). Worth verifying because
  this brand color is reused for CTAs across the app.

### F2 (serious): `link-name` — WCAG 2.0 A (2.4.4, 4.1.2) — Sign In, Create Account

The logo/home link is in the tab order but exposes **no accessible name** to
assistive technology:

```html
<a href="/" class="group"> … </a>
```

Add an accessible name — e.g. `aria-label="Onetime Secret — home"` — or ensure
the inner logo text/SVG is exposed to screen readers rather than
`aria-hidden`.

### F3 (moderate): `page-has-heading-one` — best-practice — Sign In, Create Account, Forgot Password

These auth pages have **no `<h1>`**. The visible page title ("Sign In",
"Create Account", "Reset your password") should be — or contain — an `<h1>`
so the page exposes a top-level heading landmark.

### F4 (moderate): `heading-order` — best-practice — Home, Pricing, Feedback

Heading levels **skip** (e.g. Home jumps to `<h3>` for the "Passphrase" field
label; Pricing/Feedback use `<h3>` with no `<h2>`/`<h1>` above). Several of
these `<h3>`s are really styled form labels — either demote them to a
non-heading element or correct the hierarchy so levels increase by one.

## 4. Needs manual review

axe reported these as **incomplete** (it could not decide automatically); each
warrants a human check.

- **`aria-valid-attr-value` (critical if confirmed)** — Home's split-button
  "Show more actions" dropdown and a `role="complementary"` block on Feedback
  reference an `aria-*` id target axe could not resolve at snapshot time.
  Verify the referenced IDs actually exist in the rendered DOM.
- **`aria-prohibited-attr` (serious)** — Home has several `<div>`s carrying
  `aria-label` / `aria-labelledby` without a `role` (`Create Secret Link`,
  `secretContentLabel`, `recent-secrets-heading`), where those attributes are
  not reliably announced. Add an appropriate `role` (e.g. `group`/`region`) or
  move the label onto a semantic element.
- **`color-contrast` (incomplete)** — 13 nodes on Home, Sign In, and Forgot
  Password could not be evaluated automatically (e.g. text over a
  gradient/background image). Confirm these manually.

## 5. Caveats

- **Automated only.** axe surfaces roughly 30–40% of WCAG issues. This is a
  strong baseline, not a complete audit — keyboard navigation, focus
  visibility, and screen-reader spot-checks (NVDA/VoiceOver/JAWS) still require
  manual testing (see the testing plans in
  [`OVERVIEW.md`](../development/accessibility/OVERVIEW.md)).
- ~~**Light mode only.**~~ Resolved: the standing harness (§7) now scans every
  surface in **both** light and dark themes.
- **Static post-mount snapshot.** Opened dropdowns, modals, inline
  validation-error states, and focus styles were not exercised.
- Run against the environment's pre-installed Chromium (the pinned Playwright
  browser build was not fetchable) — immaterial for axe DOM analysis.

## 6. Reproducing

With a production build served locally (see
[`development/testing-build-steps.md`](../development/testing-build-steps.md))
and a test datastore running:

```bash
# 1. serve a production build (built assets in public/web/dist)
RACK_ENV=production REDIS_URL=redis://127.0.0.1:2121/0 SECRET=$(openssl rand -hex 32) \
  HOST=localhost:7143 SSL=false AUTH_AUTOVERIFY=true EMAILER_MODE=logger \
  bundle exec bin/ots server --port 7143

# 2. run the standing a11y suite (see §7)
pnpm test:a11y            # scans all 6 surfaces × light/dark against the baseline
pnpm test:a11y:update     # regenerate the baseline after an intentional change
```

## 7. Resolution & ongoing enforcement

The findings above were fixed and, rather than leaving accessibility as a
point-in-time check, folded into the test suite so the score is maintained.

**Fixes (public surfaces, light + dark → zero axe violations):** darkened the
footer release-notes text and the "Send Reset Link" / brand-`600` buttons for
contrast; gave the logo home-link an accessible name; promoted auth-page
titles to `<h1>` and corrected heading order (form labels demoted, section
headings normalised to `<h2>`); added `role="group"` where `aria-label`/
`aria-labelledby` landed on bare `<div>`s and made `SplitButton`'s
`aria-controls` conditional on the dropdown being open; and added `dark:`
contrast variants for the feedback list, signup legal links, and the
return-home link.

**Standing test layers:**

- **Page-level (browser truth)** — `e2e/all/accessibility.spec.ts` drives
  axe-core (via `@axe-core/playwright`) over all six public surfaces in **both
  light and dark** themes (12 checks). It compares against a ratcheting
  baseline (`e2e/accessibility-baseline.json`, currently **empty**): the suite
  fails on any violation not in the baseline and hard-fails on any new
  `serious`/`critical` one. `pnpm test:a11y` runs it; `pnpm test:a11y:update`
  regenerates the baseline after an intentional change. It runs in CI as part
  of the existing `e2e/all/` gate (`.github/workflows/e2e.yml`).
- **Component-level (shift-left)** — `src/tests/shared/a11y/*.a11y.spec.ts`
  run axe-core in jsdom (via `vitest-axe`) against shared UI primitives
  (buttons, form fields, `SplitButton`, footer, …) as part of the standard
  `pnpm test` (Vitest) run, catching structural/ARIA/label regressions at the
  component before they reach a page. Contrast is excluded here (jsdom has no
  layout) and remains the page-level layer's job.

**Still manual (not automated):** keyboard-only navigation, focus visibility,
and screen-reader spot-checks (NVDA/VoiceOver/JAWS) — see `OVERVIEW.md`.
