// e2e/visual/notfound.spec.ts
//
// Visual baselines for the generic 404 page across canonical and branded
// hosts. Uses a static non-route path (non-alphanumeric segments never
// reach the UnknownSecret flow — that page is covered by secret--unknown).

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

test.describe('Visual - Not found page', () => {
  for (const fixture of FIXTURES) {
    test(`notfound--default--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];

      const response = await gotoAndReady(page, visualUrl(host, '/this-page-does-not-exist'));
      await assertBrandRendered(page, fixture, response, { expectBrandElement: false });

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`notfound--default--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }
});
