// e2e/visual/receipt.spec.ts
//
// Visual baselines for the sender-facing receipt page (/receipt/:id):
//  - fresh: unrevealed secret with share link. The first view stamps
//    receipt_viewed_at, so each viewport consumes its own manifest record.
//  - viewed: recipient already revealed the secret (terminal state, safe
//    to share; desktop only per the matrix)
//  - burned: sender burned the secret (terminal state; desktop only)
//
// Receipt pages render brand colors on custom domains but no brand
// identity element (logo/instructions) in the page body — the
// O-Domain-Strategy header assertion is the brand guard here.

import { test, expect } from '@playwright/test';
import {
  DESKTOP_ONLY_FIXTURES,
  FIXTURES,
  assertBrandRendered,
  collectConsoleErrors,
  gotoAndReady,
  loadManifest,
  viewportKey,
  visualMasks,
  visualUrl,
} from './support';

test.describe('Visual - Receipt page', () => {
  for (const fixture of FIXTURES) {
    test(`receipt--fresh--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { receiptId } = manifest.cells[fixture].receiptFresh[viewportKey(test.info())];

      const response = await gotoAndReady(page, visualUrl(host, `/receipt/${receiptId}`));
      await assertBrandRendered(page, fixture, response, { expectBrandElement: false });

      // Real receipt rendered, not the UnknownReceipt fallback.
      await expect(page.getByTestId('receipt-status')).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`receipt--fresh--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }

  for (const fixture of DESKTOP_ONLY_FIXTURES) {
    test(`receipt--viewed--${fixture}`, { tag: '@desktop-only' }, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { receiptId } = manifest.cells[fixture].receiptViewed;

      const response = await gotoAndReady(page, visualUrl(host, `/receipt/${receiptId}`));
      await assertBrandRendered(page, fixture, response, { expectBrandElement: false });
      await expect(page.getByTestId('receipt-status')).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`receipt--viewed--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });

    test(`receipt--burned--${fixture}`, { tag: '@desktop-only' }, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { receiptId } = manifest.cells[fixture].receiptBurned;

      const response = await gotoAndReady(page, visualUrl(host, `/receipt/${receiptId}`));
      await assertBrandRendered(page, fixture, response, { expectBrandElement: false });
      await expect(page.getByTestId('receipt-status')).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`receipt--burned--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }
});
