// e2e/visual/home.spec.ts
//
// Visual baselines for the homepage (/) across canonical and branded hosts.
// Canonical renders the marketing homepage; custom domains render
// BrandedHomepage (hero + form/trust card).

import { test, expect } from '@playwright/test';
import {
  FIXTURES,
  assertBrandRendered,
  collectConsoleErrors,
  gotoAndReady,
  loadManifest,
  visualMasks,
  visualUrl,
} from './support';

test.describe('Visual - Homepage', () => {
  for (const fixture of FIXTURES) {
    test(`home--default--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);

      const response = await gotoAndReady(page, visualUrl(manifest.fixtures[fixture].host, '/'));

      // branded-edge is logo-less by design and its homepage hero renders
      // neither brand-logo nor brand-instructions; the O-Domain-Strategy
      // header assertion inside the helper is the guard there.
      await assertBrandRendered(page, fixture, response, {
        expectBrandElement: fixture === 'branded-full',
      });

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`home--default--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }
});
