// e2e/visual/secret.spec.ts
//
// Visual baselines for the recipient-facing secret page (/secret/:id):
//  - confirm: the click-to-reveal confirmation view (metadata-only GET,
//    safe to share one record across viewports)
//  - revealed: post-click revealed content (destroys the secret, so each
//    viewport consumes its own manifest sub-record)
//  - passphrase: confirmation view with the passphrase input rendered
//    (has_passphrase); screenshot as-is, never fill or submit
//  - unknown: a fabricated-but-well-formed id that 404s to UnknownSecret
//    (identical to viewed/expired, by design)

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

test.describe('Visual - Secret page', () => {
  for (const fixture of FIXTURES) {
    test(`secret--confirm--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { secretId } = manifest.cells[fixture].revealConfirm;

      const response = await gotoAndReady(page, visualUrl(host, `/secret/${secretId}`));
      await assertBrandRendered(page, fixture, response);
      await expect(page.getByTestId('secret-reveal-submit')).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`secret--confirm--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });

    test(`secret--revealed--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { secretId } = manifest.cells[fixture].revealRevealed[viewportKey(test.info())];

      const response = await gotoAndReady(page, visualUrl(host, `/secret/${secretId}`));
      await assertBrandRendered(page, fixture, response);

      // Click-through: consumes (destroys) this viewport's secret record.
      await page.getByTestId('secret-reveal-submit').click();
      await expect(page.getByTestId('secret-content')).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`secret--revealed--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });

    test(`secret--unknown--${fixture}`, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];

      const response = await gotoAndReady(
        page,
        visualUrl(host, `/secret/${manifest.unknownSecretId}`)
      );
      // UnknownSecret renders no brand identity element (branded variant
      // included) — the strategy header is the brand guard here.
      await assertBrandRendered(page, fixture, response, { expectBrandElement: false });

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`secret--unknown--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }

  for (const fixture of DESKTOP_ONLY_FIXTURES) {
    test(`secret--passphrase--${fixture}`, { tag: '@desktop-only' }, async ({ page }) => {
      const manifest = loadManifest();
      const consoleErrors = collectConsoleErrors(page);
      const { host } = manifest.fixtures[fixture];
      const { secretId } = manifest.cells[fixture].revealPassphrase;

      const response = await gotoAndReady(page, visualUrl(host, `/secret/${secretId}`));
      await assertBrandRendered(page, fixture, response);

      // has_passphrase makes the input render on the confirmation view.
      // Screenshot as-is — do NOT fill or submit (submitting would consume
      // the shared record). The branded input carries no testid (the src/
      // diff for this suite is deliberately limited), so fall back to its
      // name attribute there.
      const passphraseInput =
        fixture === 'canonical'
          ? page.getByTestId('secret-reveal-passphrase-input')
          : page.locator('input[name="passphrase"]');
      await expect(passphraseInput).toBeVisible();

      expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

      await expect(page).toHaveScreenshot(`secret--passphrase--${fixture}.png`, {
        fullPage: true,
        mask: visualMasks(page),
      });
    });
  }
});
