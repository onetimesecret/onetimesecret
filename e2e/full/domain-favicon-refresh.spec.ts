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

import { expect, Page, test } from '@playwright/test';

import { env, gateReason } from '../support/env';

test.beforeEach(() => {
  test.skip(!env.hasCustomDomains, gateReason.customDomains);
});

// -----------------------------------------------------------------------------
// Types + helpers (mirrors e2e/full/domain-navigation.spec.ts)
// -----------------------------------------------------------------------------

interface OrgInfo {
  extid: string;
}

interface DomainInfo {
  extid: string;
  displayDomain: string;
}

async function getFirstOrganization(page: Page): Promise<OrgInfo | null> {
  await page.goto('/orgs');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  const orgLink = page.locator('a[href*="/org/"]').first();
  if (!(await orgLink.isVisible().catch(() => false))) return null;

  const href = await orgLink.getAttribute('href');
  const match = href?.match(/\/org\/([^/]+)/);
  return match ? { extid: match[1] } : null;
}

async function getFirstDomain(page: Page, orgExtid: string): Promise<DomainInfo | null> {
  await page.goto(`/org/${orgExtid}/domains`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  const domainLink = page.locator('a[href*="/domains/"]').first();
  if (!(await domainLink.isVisible().catch(() => false))) return null;

  const href = await domainLink.getAttribute('href');
  const match = href?.match(/\/domains\/([^/]+)/);
  if (!match) return null;

  const domainText = await domainLink.locator('.font-medium, .truncate').first().textContent();
  return { extid: match[1], displayDomain: domainText?.trim() || match[1] };
}

/**
 * Navigate to the Brand page and resolve the refresh-favicon button, or null
 * when the account lacks the custom_branding entitlement (the page renders an
 * access block instead of the editor). Simple is the default brand path, so the
 * button is present without switching tabs.
 */
async function gotoBrandRefreshButton(page: Page, org: OrgInfo, domain: DomainInfo) {
  await page.goto(`/org/${org.extid}/domains/${domain.extid}/brand`);
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

  const button = page.getByTestId('domain-favicon-refresh');
  // The editor (and this button) mount only after useBranding.initialize()
  // finishes its awaited fetch chain (fetchList → fetchSettings → fetchLogo),
  // which resolves AFTER data-app-ready. Use a RETRYING wait, not a one-shot
  // isVisible(): the latter races the in-flight fetches and would return null
  // on a fully-entitled target, skipping every test vacuously with a false
  // "not entitled" reason. A real timeout here means the button genuinely
  // never rendered — i.e. the account lacks the custom_branding entitlement.
  const appeared = await button
    .waitFor({ state: 'visible', timeout: 12000 })
    .then(() => true)
    .catch(() => false);
  return appeared ? button : null;
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
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    const button = await gotoBrandRefreshButton(page, org!, domain!);
    test.skip(!button, 'Brand editor unavailable — requires the custom_branding entitlement');

    await expect(button!).toBeVisible();
    // The hint always renders next to the button (default or user_upload copy).
    await expect(page.getByTestId('domain-favicon-hint')).toBeVisible();
  });

  test('TC-FAV-002: button disabled-state agrees with the provenance hint', async ({ page }) => {
    // The crux of the schema wiring: the gate reads icon.favicon_source, which
    // only reaches the record now that safe_dump projects it. Whichever state
    // this domain is in, the button's disabled flag and the hint copy must
    // agree — a user_upload icon disables + explains; otherwise it stays live.
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    const button = await gotoBrandRefreshButton(page, org!, domain!);
    test.skip(!button, 'Brand editor unavailable — requires the custom_branding entitlement');

    const isDisabled = await button!.isDisabled();
    const hint = (await page.getByTestId('domain-favicon-hint').textContent())?.toLowerCase() ?? '';

    if (isDisabled) {
      // user_upload copy: "...a fetched icon won't replace it."
      expect(hint).toContain("won't replace");
    } else {
      // default copy: "Fetch the favicon from your domain again..."
      expect(hint).toContain('fetch the favicon');
    }
  });

  test('TC-FAV-003: clicking an enabled refresh queues a fetch (POST + toast)', async ({ page }) => {
    const org = await getFirstOrganization(page);
    test.skip(!org, 'Test requires at least 1 organization');

    const domain = await getFirstDomain(page, org!.extid);
    test.skip(!domain, 'Test requires at least 1 domain');

    const button = await gotoBrandRefreshButton(page, org!, domain!);
    test.skip(!button, 'Brand editor unavailable — requires the custom_branding entitlement');

    // A user_upload icon disables the control (nothing to queue) — that path is
    // covered by TC-FAV-002; here we only exercise the queue-able state.
    test.skip(await button!.isDisabled(), 'Icon is user-uploaded — refresh is (correctly) disabled');

    const refreshPost = page.waitForResponse(
      (res) =>
        /\/domains\/[^/]+\/icon\/refresh$/.test(res.url()) && res.request().method() === 'POST',
      { timeout: 15000 }
    );

    await button!.click();

    const response = await refreshPost;
    expect(response.ok(), `refresh POST should succeed, got ${response.status()}`).toBe(true);

    // The queued success surfaces as a polite status toast (NotificationCard).
    await expect(page.locator('[role="status"]').first()).toBeVisible();
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
 */
