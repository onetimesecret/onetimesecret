// e2e/visual/incoming.spec.ts
//
// Visual baselines for the incoming-secrets flow, canonical host only:
//  - form: /incoming (env contract guarantees INCOMING_ENABLED=true, so a
//    disabled/entitlement-blocked render MUST fail the test)
//  - success: /incoming/:receiptId — IncomingSuccess renders purely from
//    the route param, so the shared manifest record is viewport-safe.

import { test, expect } from '@playwright/test';
import {
  assertBrandRendered,
  collectConsoleErrors,
  gotoAndReady,
  loadManifest,
  visualMasks,
  visualUrl,
} from './support';

test.describe('Visual - Incoming secrets', () => {
  test('incoming--form--canonical', async ({ page }) => {
    const manifest = loadManifest();
    const consoleErrors = collectConsoleErrors(page);

    const response = await gotoAndReady(page, visualUrl(manifest.canonicalHost, '/incoming'));
    await assertBrandRendered(page, 'canonical', response);

    // The form must render — a disabled/config-error state means the env
    // contract (INCOMING_ENABLED + INCOMING_RECIPIENT_1) was not honored.
    await expect(page.getByTestId('incoming-form')).toBeVisible();

    expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

    await expect(page).toHaveScreenshot('incoming--form--canonical.png', {
      fullPage: true,
      mask: visualMasks(page),
    });
  });

  test('incoming--success--canonical', async ({ page }) => {
    const manifest = loadManifest();
    const consoleErrors = collectConsoleErrors(page);
    const { receiptId } = manifest.cells['canonical'].incomingSuccess;

    const response = await gotoAndReady(
      page,
      visualUrl(manifest.canonicalHost, `/incoming/${receiptId}`)
    );
    await assertBrandRendered(page, 'canonical', response);

    // Reference id renders (masked below — it changes every seed run).
    await expect(page.getByTestId('incoming-reference-id')).toBeVisible();

    expect(consoleErrors(), 'no console errors before screenshot').toEqual([]);

    await expect(page).toHaveScreenshot('incoming--success--canonical.png', {
      fullPage: true,
      mask: visualMasks(page),
    });
  });
});
