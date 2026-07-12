# docs/specs/qa/visual-regressions/qa-visual-regressions-approach.md

---

## Decision

Use Playwright's built-in `toHaveScreenshot()` for visual regression on customer-visible pages. Do not adopt BackstopJS. Do not adopt Storybook.

The risk you're protecting against is not component drift — it's the **domain → brand config → rendered page** pipeline breaking for B2B customers and their B2B2C recipients. That pipeline only exists in the running app, so the test has to exercise the running app. Component-level tooling can't see it.

## Why not the alternatives

**BackstopJS** now uses Playwright as its rendering engine. Adopting it means a second config format, a second baseline directory convention, and a second approval workflow wrapped around the same browser you'd run directly. Its one genuine advantage — `referenceUrl` for prod-vs-staging comparison without committed baselines — is reproducible in Playwright with two runs of the same spec (see §6). For a solo maintainer, one tool that does 100% beats two tools that overlap 90%.

**Storybook** is a parallel implementation of your UI that must be kept in sync by hand. That's a standing tax with no payoff here: stories render components with props you invent, not with brand settings resolved from a real domain record. It shines when a team needs a shared component catalog. You are the team. Defer indefinitely — but note the deferral is not a claim that component consistency doesn't matter. It's that Storybook is a *viewing* instrument for consistency, and a growing component surface calls for *enforcement* instruments (see "Component consistency" below).

## 1. Test matrix — small and fixed

The failure surface is `pages × brand configurations`, so pick representative fixtures rather than trying to cover pages exhaustively.

**Brand fixtures:**

| Fixture        | Purpose                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| `canonical`    | Default OTS branding on the primary domain                                                             |
| `branded-full` | Custom domain with primary color, logo, custom instructions, font/corner settings all set              |
| `branded-edge` | Dark primary color, long instruction text, non-English locale — the config most likely to break layout |

**Pages per fixture:**

- Homepage / secret creation (what the B2B customer's users see)
- Secret link preview page
- Secret reveal page (the B2B2C surface — recipients who never chose OTS see this one)
- Burn / receipt page
- 404 and "unknown secret" error pages on the custom domain

Roughly 5 pages × 3 fixtures × 2 viewports (desktop 1280px, mobile 375px) ≈ **30 screenshots**. Full run should stay under a couple of minutes. Resist expanding this; the value is in the branded-domain coverage, not breadth.

## 2. Simulating custom domains locally

No DNS needed. Map fixture hostnames to localhost via Chromium's resolver:

```ts
// playwright.config.ts (visual project)
export default defineConfig({
  projects: [
    {
      name: 'visual',
      testMatch: /visual\/.*\.spec\.ts/,
      use: {
        launchOptions: {
          args: ['--host-resolver-rules=MAP *.ots.test 127.0.0.1'],
        },
        viewport: { width: 1280, height: 800 },
        reducedMotion: 'reduce',
      },
    },
  ],
});
```

```ts
test('branded homepage', async ({ page }) => {
  await page.goto('http://secrets.acme.ots.test:3000/');
  await expect(page).toHaveScreenshot('homepage-branded-full.png', {
    fullPage: true,
    maxDiffPixels: 100,
  });
});
```

The app receives `Host: secrets.acme.ots.test` and resolves the brand exactly as production would.

**Wrong-but-green guard.** Before every branded screenshot, assert that the custom brand actually rendered — one locator check for a brand-specific element (logo alt text, primary-color element, custom instruction text):

```ts
await expect(page.locator('[data-testid="brand-logo"]')).toBeVisible();
await expect(page).toHaveScreenshot(/* ... */);
```

Without this, a Host→brand resolution miss falls back to canonical branding and every branded screenshot silently captures the default UI — the suite stays green while covering nothing. This is the cheapest insurance in the whole plan; the screenshot alone cannot distinguish "brand rendered" from "fallback rendered" on the first baseline run.

## 3. Fixture seeding

- Seed in Playwright `globalSetup`, not per-test `beforeEach`. The brand configs are shared read-only state; per-test datastore flushes would wipe them mid-run. The visual suite must not flush the test datastore at all — it reads, it doesn't mutate.
- Seed through the model layer (a rake task creating `CustomDomain` records + brand config via the app's own persistence code), **not** raw Redis writes. Raw writes drift from the shape the app actually produces, and the test ends up passing against data production never generates. Note: don't seed through the full domain-creation API flow either — ownership verification won't pass for `*.ots.test` hostnames; the model layer sidesteps the verification gate while keeping the persistence shape honest.
- Seed secrets with known keys in the same setup so reveal/receipt pages render identical URLs.

## 4. Determinism rules

- `reducedMotion: 'reduce'` in config (above) kills transitions.
- `mask` anything time-relative (TTL countdowns, "expires in X hours").
- Expect to add 1–2 masks on the first bootstrap run (visible generated identifiers, asset-load timing artifacts). Don't pre-engineer the mask list — grow it from real diffs.
- Generate baselines **only** inside the CI Linux container (or Docker locally). Never commit darwin baselines — font rendering differs and you'll chase phantom diffs. A `make visual` target that runs the Playwright Docker image keeps this honest.
- `maxDiffPixels` over `threshold` for full-page shots — it maps directly to "how much changed."

## 5. Workflow

```bash
make visual                        # run against baselines
npx playwright test --update-snapshots  # after intentional UI changes, in Docker
git add tests/visual/__snapshots__      # baselines are source code
```

CI: run the visual project on PRs touching frontend paths; upload `test-results/` as an artifact on failure so the diff images are one click away.

## 6. Immediate: gating v0.26.0

You don't need the long-term habit in place to answer this week's question. Same spec, two builds:

1. `git worktree add ../ots-v0.25 v0.25.x` — run it, seed fixtures, `--update-snapshots` against it. These baselines are "what customers see today."
2. Point the spec at your v0.26.0 build and run `npx playwright test`. Every diff in the report is a customer-visible change in the release — triage each as intentional or regression.
3. Approve the intentional ones as the new baselines and you've bootstrapped the permanent suite as a side effect of the release check.

## Component consistency — enforce, don't catalog

Screenshot tests catch pipeline breakage; they don't manage consistency across a growing component surface. Neither does a catalog: Storybook *documents* consistency, and a catalog of 150 stories drifts as fast as the components do. For a solo maintainer the sync tax and the benefit land on the same person — the economics never invert the way they do on a team where one author pays and ten consumers benefit.

Consistency is managed by making drift structurally hard, at the point of authorship:

- **Shared primitives over duplicated markup.** When a pattern appears a third time, extract it (field shells, modal/panel kits). Consistency enforced at the import site, not observed in a catalog.
- **Design tokens over literal values.** A component can't drift from a token it consumes; a hardcoded `blue-500` can. Tokenize on contact.
- **Lint and type gates in CI.** Cheap, mechanical, don't rot. Ratchet rules when a new class of drift shows up.

**When to revisit Storybook:** a second regular frontend contributor, or a design-review loop where someone non-technical needs to browse component states without running the app. Those are the team-catalog cases where the economics flip. Until one exists, catalog effort is better spent on the three levers above.

## Guardrails

Things this deliberately does not include, and shouldn't grow to include without a concrete failure motivating it: cross-browser matrix (chromium only), per-component screenshots, Percy/Chromatic SaaS, Storybook. The transactional email brand surface (footers, `powered_by` locale) is also out of scope — there's no Playwright page to screenshot; revisit with a separate rendered-email harness if it keeps regressing. When a customer reports a brand config that broke and wasn't covered, add it as a fourth fixture — that's the only sanctioned growth path.

One limitation to keep in mind: screenshots only catch what you screenshot. If a regression serves the _wrong_ brand entirely, the diff catches it; if it breaks a page not in the matrix, nothing does. The fixture list is the contract — keep it honest, keep it short.
