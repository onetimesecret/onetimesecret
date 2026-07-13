// e2e/visual/burn.spec.ts
//
// Visual baselines for the burn confirmation page (/receipt/:id/burn).
// Loading the page fetches the receipt (stamping its first view), so each
// viewport consumes its own manifest sub-record. The screenshot captures
// the confirmation form only — the burn is never submitted.

import { test, expect } from '@playwright/test';
import {
  FIXTURES,
  assertBrandRendered,
  collectConsoleErrors,
  gotoAndReady,
  loadManifest,
  viewportKey,
  visualMasks,
  visualUrl,
} from './support';

test.describe('Visual - Burn page', () => {
  for (const fixture of FIXTURES) {
    test(`burn--confirm--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { receiptId } = manifest.cells[fixture].burnPage[viewportKey(test.info())];

      const response = await gotoAndReady(page, visualUrl(host, `/receipt/${receiptId}/burn`));
      await assertBrandRendered(page, fixture, response, { expectBrandElement: false });

      // Active-secret state rendered (destroyed/invalid state has no form).
      // Testid, not button text: branded-edge renders in German (brand
      // locale 'de'), so any English-text locator fails on it by design.
      await expect(page.getByTestId('burn-page-submit')).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`burn--confirm--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page, [
          // "Secret: <shortid>" heading — shortid is generated per run.
          page.getByRole('heading', { level: 2 }),
        ]),
      });
    });
  }
});
