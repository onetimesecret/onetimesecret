// e2e/support/domains.ts
//
// Shared lookup of an organization's first custom domain for the e2e/full/
// domain suites. It replaces five identical per-spec getFirstDomain() copies
// that read /org/:extid/domains with an isVisible() snapshot and returned
// null, which every caller turned into a runtime
// test.skip('Test requires at least 1 domain'). Those copies also took the
// first `a[href*="/domains/"]` on the page, which is the panel's
// "Add Domain" link (/org/:extid/domains/add) whenever a domain exists.
//
// Only the suites gated on E2E_CUSTOM_DOMAINS (e2e/support/env.ts) call this.
// That flag promises a custom domain on the test account, so a missing one
// fails the test instead of skipping it.

import { expect, type Page } from '@playwright/test';

export interface DomainInfo {
  extid: string;
  displayDomain: string;
}

/**
 * Open the organization's Domains tab, wait for its domain table, and return
 * the first custom domain's extid and name. Leaves the page on the tab.
 */
export async function getFirstDomain(page: Page, orgExtid: string): Promise<DomainInfo> {
  await page.goto(`/org/${orgExtid}/domains`);

  // The domain name links to its detail page, /org/:orgid/domains/:extid
  const detailLink = page
    .getByTestId('org-section-domains')
    .locator('tbody tr')
    .first()
    .locator(`a[href^="/org/${orgExtid}/domains/"]`)
    .first();
  await expect(
    detailLink,
    'E2E_CUSTOM_DOMAINS: the organization lists at least one custom domain'
  ).toBeVisible();

  const href = (await detailLink.getAttribute('href')) ?? '';
  const extid = href.match(/\/domains\/([^/]+)$/)?.[1] ?? '';
  expect(extid, `domain link "${href}" carries an extid`).not.toBe('');

  const displayDomain = ((await detailLink.textContent()) ?? '').trim();
  expect(displayDomain, `domain ${extid} has a display name`).not.toBe('');

  return { extid, displayDomain };
}
