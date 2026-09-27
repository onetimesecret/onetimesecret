// e2e/full/domain-favicon-refresh.spec.ts
//
/**
 * E2E Tests for the domain favicon queued-refresh flow (#3780).
 *
 * Covers the observable half of the "Refresh favicon from domain" control on
 * the workspace Brand page:
 *   - the control renders (button + hint) on the Simple brand path;
 *   - clicking an enabled button POSTs the manual-refresh endpoint and the UI
 *     toasts the queued state (the icon lands later via the background worker,
 *     which is NOT observable here — it needs a real reachable domain);
 *   - the button's disabled-state agrees with the provenance hint. This is the
 *     payoff of the schema wiring in this change: the gate reads
 *     `customDomainRecord.icon.favicon_source`, which only reaches the frontend
 *     now that safe_dump projects it. A `user_upload` icon disables the button
 *     (the backend overwrite-guard is the real protection); anything else
 *     leaves it enabled.
 *
 * Prerequisites (same gate as the other domain suites):
 *   - Authenticated via the project storageState (e2e/global.setup.ts).
 *   - A custom domain on the test account AND the custom_branding entitlement.
 *
 * DORMANT in CI: no lane sets E2E_CUSTOM_DOMAINS yet (see e2e/support/env.ts
 * and issue #3420). Run against a domains-enabled target:
 *   E2E_CUSTOM_DOMAINS=1 pnpm playwright test domain-favicon-refresh.spec.ts
 */

import { expect, type Locator, type Page, test } from '@playwright/test';

import { env, gateReason } from '../support/env';
import { getFirstDomain, type DomainInfo } from '../support/domains';
import { getFirstOrganization, type OrgInfo } from '../support/organizations';

test.beforeEach(() => {
  test.skip(!env.hasCustomDomains, gateReason.customDomains);
});

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/**
 * Navigate to the Brand page and return the refresh-favicon button. Simple is
 * the default brand path, so the button is present without switching tabs.
 *
 * The editor (and this button) mount only after useBranding.initialize()
 * finishes its awaited fetch chain (fetchList, fetchSettings, fetchLogo),
 * which resolves after data-app-ready, so the wait retries. An account
 * without the custom_branding entitlement gets an access block instead; the
 * E2E_CUSTOM_DOMAINS target must grant it (standalone installs grant every
 * entitlement).
 */
async function gotoBrandRefreshButton(
  page: Page,
  org: OrgInfo,
  domain: DomainInfo
): Promise<Locator> {
  await page.goto(`/org/${org.extid}/domains/${domain.extid}/brand`);

  const button = page.getByTestId('domain-favicon-refresh');
  await expect(
    button,
    'the Brand editor renders (the account has the custom_branding entitlement)'
  ).toBeVisible({ timeout: 12000 });
  return button;
}

// -----------------------------------------------------------------------------
// Test Suite
// -----------------------------------------------------------------------------

test.describe('Domain favicon refresh (#3780)', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('TC-FAV-001: refresh-favicon control renders on the Brand page', async ({ page }) => {
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    const button = await gotoBrandRefreshButton(page, org, domain);

    await expect(button).toBeVisible();
    // The hint always renders next to the button (default or user_upload copy).
    await expect(page.getByTestId('domain-favicon-hint')).toBeVisible();
  });

  test('TC-FAV-002: button disabled-state agrees with the provenance hint', async ({ page }) => {
    // The crux of the schema wiring: the gate reads icon.favicon_source, which
    // only reaches the record now that safe_dump projects it. Whichever state
    // this domain is in, the button's disabled flag and the hint copy must
    // agree — a user_upload icon disables + explains; otherwise it stays live.
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    const button = await gotoBrandRefreshButton(page, org, domain);

    const isDisabled = await button.isDisabled();
    const hint = (await page.getByTestId('domain-favicon-hint').textContent())?.toLowerCase() ?? '';

    if (isDisabled) {
      // user_upload copy: "...a fetched icon won't replace it."
      expect(hint).toContain("won't replace");
    } else {
      // default copy: "Fetch the favicon from your domain again..."
      expect(hint).toContain('fetch the favicon');
    }
  });

  test('TC-FAV-003: clicking an enabled refresh queues a fetch (POST + toast)', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    const button = await gotoBrandRefreshButton(page, org, domain);

    // A user_upload icon disables the control (nothing to queue) — that path is
    // covered by TC-FAV-002; this test needs the queue-able state. TC-FAV-004
    // uploads an icon, so a target reused across runs must reset it.
    await expect(
      button,
      "the domain's favicon is not user-uploaded (refresh stays enabled)"
    ).toBeEnabled();

    const refreshPost = page.waitForResponse(
      (res) =>
        /\/domains\/[^/]+\/icon\/refresh$/.test(res.url()) && res.request().method() === 'POST',
      { timeout: 15000 }
    );

    await button.click();

    const response = await refreshPost;
    expect(response.ok(), `refresh POST should succeed, got ${response.status()}`).toBe(true);

    // The queued success surfaces as a polite status toast (NotificationCard).
    await expect(page.locator('[role="status"]').first()).toBeVisible();
  });

  // 1x1 transparent PNG — small, valid, FastImage-measurable, and on the icon
  // allowlist (image/png). Used as the uploaded favicon payload.
  const ONE_BY_ONE_PNG = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    'base64'
  );

  test('TC-FAV-004: uploading a favicon commits synchronously and the two controls coexist', async ({
    page,
  }) => {
    // The upload counterpart to the refresh button (#3780). Unlike the queued
    // refresh (TC-FAV-003), the upload is a SYNCHRONOUS store write: the POST
    // /icon returns the stored record immediately, so the preview flip is
    // deterministic here and does NOT depend on the background worker.
    const org = await getFirstOrganization(page);

    const domain = await getFirstDomain(page, org.extid);

    // Reuse the entitlement gate: if the refresh button mounted, the whole
    // Simple panel (including the upload field) did too.
    const refreshButton = await gotoBrandRefreshButton(page, org, domain);

    const uploadButton = page.getByTestId('domain-favicon-upload');

    // Coexistence: BOTH the new upload field and the existing refresh control
    // are present on the Simple brand path.
    await expect(uploadButton).toBeVisible();
    await expect(refreshButton).toBeVisible();

    // Open the staged-upload modal, pick the PNG, and commit.
    await uploadButton.click();
    const dialog = page.locator('[role="dialog"]');
    await expect(dialog).toBeVisible();

    await dialog.locator('input[type="file"]').setInputFiles({
      name: 'favicon.png',
      mimeType: 'image/png',
      buffer: ONE_BY_ONE_PNG,
    });

    // The confirm CTA enables only once a file is staged.
    const saveButton = dialog.getByRole('button', { name: /save favicon/i });
    await expect(saveButton).toBeEnabled();

    const uploadPost = page.waitForResponse(
      (res) => /\/domains\/[^/]+\/icon$/.test(res.url()) && res.request().method() === 'POST',
      { timeout: 15000 }
    );

    await saveButton.click();

    const response = await uploadPost;
    expect(response.ok(), `icon upload POST should succeed, got ${response.status()}`).toBe(true);

    // On success the modal closes and the field flips Upload → Replace, proving
    // the preview reflects the newly-stored icon (no worker round-trip needed).
    await expect(dialog).toBeHidden();
    await expect(uploadButton).toContainText(/replace favicon/i);
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Domain favicon refresh (#3780)
 *
 * | ID         | Title                                                     | Priority | Automation |
 * |------------|-----------------------------------------------------------|----------|------------|
 * | TC-FAV-001 | Refresh-favicon control renders on the Brand page         | Medium   | Automated  |
 * | TC-FAV-002 | Button disabled-state agrees with the provenance hint     | High     | Automated  |
 * | TC-FAV-003 | Clicking an enabled refresh queues a fetch (POST + toast) | High     | Automated  |
 * | TC-FAV-004 | Uploading a favicon commits synchronously; controls coexist | High   | Automated  |
 */
