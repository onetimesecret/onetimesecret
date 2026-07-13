# docs/specs/qa/visual-regressions/qa-visual-regressions-playwright.md

---

For customer-visible pages, Playwright’s built-in visual regression testing is the cleanest approach. It compares a rendered screenshot against a committed baseline and fails the test if pixels differ beyond a threshold.

Here is a practical setup.

## 1. Basic test

Use `toHaveScreenshot()` on a page or locator:

```ts
import { test, expect } from '@playwright/test';

test('homepage looks correct', async ({ page }) => {
  await page.goto('https://your-site.com/');
  await expect(page).toHaveScreenshot('homepage.png');
});
```

For a single component or customer-visible card:

```ts
const card = page.locator('[data-testid="pricing-card"]');
await expect(card).toHaveScreenshot('pricing-card.png');
```

## 2. Update baselines

When a change is intentional, regenerate the baseline images:

```bash
bin/visual --update    # wraps `npx playwright test --update-snapshots` in the pinned Linux container
```

Commit the resulting `*-linux.png` files under `e2e/visual/*-snapshots/`. Treat them as source code. (Never run `--update-snapshots` bare on macOS — darwin baselines are phantom-diff generators and must not be committed.)

## 3. Stabilize screenshots

Customer pages often have animations, dynamic content, or dates. Unstable screenshots create false failures.

| Source of flakiness | Fix                                                                                          |
| ------------------- | -------------------------------------------------------------------------------------------- |
| Animations          | `await page.emulateMedia({ reducedMotion: 'reduce' })` or disable CSS animations in test env |
| Loading states      | House rule: `await expect(page.locator('html[data-app-ready="true"]')).toBeAttached()` after every `goto` — never `networkidle` or `waitForTimeout` (e2e/global.setup.ts:26-28: "waits on `html[data-app-ready=\"true\"]` (set in src/main.ts after mount + brand theme application + router.isReady()) — never `networkidle` or `waitForTimeout`") |
| Fonts               | Use consistent fonts; load web fonts before screenshot                                       |
| Dates / times       | Mock `Date.now()` or freeze time in the app                                                  |
| Viewport            | Pin viewport in `playwright.config.ts`                                                       |
| Dynamic content     | Stub APIs or hide volatile elements with `mask`                                              |

Example with masking:

```ts
await expect(page).toHaveScreenshot('dashboard.png', {
  mask: [page.locator('[data-testid="live-feed"]')],
  maskColor: '#F0F0F0',
});
```

## 4. Tolerate acceptable variance

Set thresholds so tiny anti-aliasing differences do not fail the build:

```ts
await expect(page).toHaveScreenshot('homepage.png', {
  maxDiffPixels: 100,
  threshold: 0.2,
});
```

For full-page customer pages, `maxDiffPixels` is often more useful than `threshold` because it maps directly to “how many pixels changed.”

## 5. CI strategy

In CI, run with the same OS/browser as where baselines were generated, because font and graphics rendering differ across platforms.

```yaml
- name: Run visual tests
  run: npx playwright test
- name: Upload snapshot diff
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: snapshot-diff
    path: test-results/
```

If your team uses mixed OSes, generate baselines in Linux and have developers run against those baselines in the pinned Playwright container. Here that means `bin/visual` (podman + `mcr.microsoft.com/playwright:v1.58.2-noble`); bare local runs on macOS will produce darwin diffs by design.

## 6. Recommended scope for customer pages

- **Critical paths first**: landing page, checkout, pricing, login, error pages.
- **Full-page shots** for layout regressions.
- **Locator-level shots** for reusable components (buttons, cards, modals) to isolate changes.
- **Avoid screenshots of entire dashboards** with live data unless you mask the dynamic regions.

## 7. Project structure

```
e2e/
  visual/
    pages.spec.ts
    pages.spec.ts-snapshots/
      home--default--canonical-visual-desktop-linux.png
      home--default--branded-full-visual-mobile-linux.png
```

Playwright automatically appends the project name and OS to the filename — that's how desktop/mobile baselines stay distinct (`visual-desktop` / `visual-mobile` projects) and why only `-linux.png` files belong in git.

## Quick checklist

1. Add `expect(page).toHaveScreenshot()` to critical page tests.
2. Mock dates, stub APIs, and disable animations.
3. Run `bin/visual --update` after intentional UI changes.
4. Commit baselines and diff artifacts from CI.
5. Pin the CI environment that generates the canonical baselines.

If you want, I can tailor this to a specific stack (React/Vue, Next.js, GitHub Actions, Docker, etc.) or show how to split visual tests from functional tests so they do not slow down the main suite.
