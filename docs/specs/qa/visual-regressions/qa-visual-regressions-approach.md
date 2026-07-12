# docs/specs/qa/visual-regressions/qa-visual-regressions-approach.md

---

## Decision

Use Playwright's built-in `toHaveScreenshot()` for visual regression on customer-visible pages. Do not adopt BackstopJS. Do not adopt Storybook.

The risk you're protecting against is not component drift — it's the **domain → brand config → rendered page** pipeline breaking for B2B customers and their B2B2C recipients. That pipeline only exists in the running app, so the test has to exercise the running app. Component-level tooling can't see it.

## Why not the alternatives

**BackstopJS** now uses Playwright as its rendering engine. Adopting it means a second config format, a second baseline directory convention, and a second approval workflow wrapped around the same browser you'd run directly. Its one genuine advantage — `referenceUrl` for prod-vs-staging comparison without committed baselines — is reproducible in Playwright with two runs of the same spec (see §5). For a solo maintainer, one tool that does 100% beats two tools that overlap 90%.

**Storybook** is a parallel implementation of your UI that must be kept in sync by hand. That's a standing tax with no payoff here: stories render components with props you invent, not with brand settings resolved from a real domain record. It shines when a team needs a shared component catalog. You are the team. Defer indefinitely.

## 1. Test matrix — small and fixed

The failure surface is `pages × brand configurations`, so pick representative fixtures rather than trying to cover pages exhaustively.

**Brand fixtures (seeded into Redis by a test setup script):**

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

## 3. Determinism rules

- Seed secrets with known keys in test setup so reveal/receipt pages render identical URLs, or `mask` the key/URL elements.
- `reducedMotion: 'reduce'` in config (above) kills transitions.
- `mask` anything time-relative (TTL countdowns, "expires in X hours").
- Generate baselines **only** inside the CI Linux container (or Docker locally). Never commit darwin baselines — font rendering differs and you'll chase phantom diffs. A `make visual` target that runs the Playwright Docker image keeps this honest.
- `maxDiffPixels` over `threshold` for full-page shots — it maps directly to "how much changed."

## 4. Workflow

```bash
make visual                        # run against baselines
npx playwright test --update-snapshots  # after intentional UI changes, in Docker
git add tests/visual/__snapshots__      # baselines are source code
```

CI: run the visual project on PRs touching frontend paths; upload `test-results/` as an artifact on failure so the diff images are one click away.

## 5. Immediate: gating v0.26.0

You don't need the long-term habit in place to answer this week's question. Same spec, two builds:

1. `git worktree add ../ots-v0.25 v0.25.x` — run it, seed fixtures, `--update-snapshots` against it. These baselines are "what customers see today."
2. Point the spec at your v0.26.0 build and run `npx playwright test`. Every diff in the report is a customer-visible change in the release — triage each as intentional or regression.
3. Approve the intentional ones as the new baselines and you've bootstrapped the permanent suite as a side effect of the release check.

## Guardrails

Things this deliberately does not include, and shouldn't grow to include without a concrete failure motivating it: cross-browser matrix (chromium only), per-component screenshots, Percy/Chromatic SaaS, Storybook. When a customer reports a brand config that broke and wasn't covered, add it as a fourth fixture — that's the only sanctioned growth path.

One limitation to keep in mind: screenshots only catch what you screenshot. If a regression serves the _wrong_ brand entirely, the diff catches it; if it breaks a page not in the matrix, nothing does. The fixture list is the contract — keep it honest, keep it short.
