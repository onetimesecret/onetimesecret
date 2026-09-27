// e2e/support/organizations.ts
//
// Shared lookup of the signed-in account's organization for the e2e/full/
// suites. It replaces nine per-spec copies of getFirstOrganization() that
// read the /orgs page with an isVisible() snapshot taken right after
// data-app-ready. /orgs renders its list only after GET /api/organizations
// resolves, so the snapshot often saw the loading skeleton, the copies
// returned null, and every caller turned that into a runtime test.skip
// ('No organizations available', 'Test requires at least 1 organization').
// Whole suites skipped at random even though the account always owns an
// organization, and a failed-then-skipped retry sequence showed up as flaky.
//
// The account e2e/global.setup.ts signs up owns its default organization
// from signup onward, so this helper waits for the list and asserts it
// instead of returning null. A missing organization fails the test.

import { expect, type Page } from '@playwright/test';

export interface OrgInfo {
  extid: string;
  name: string;
}

/**
 * Open /orgs, wait for the organizations list to render, and return the first
 * organization card's extid and display name. Leaves the page on /orgs.
 */
export async function getFirstOrganization(page: Page): Promise<OrgInfo> {
  await page.goto('/orgs');

  const firstCard = page
    .getByTestId('organizations-list')
    .locator('[data-testid^="org-card-"]')
    .first();
  await expect(
    firstCard,
    'the signed-in account owns at least one organization (its default workspace)'
  ).toBeVisible();

  const cardTestId = await firstCard.getAttribute('data-testid');
  const extid = cardTestId?.replace(/^org-card-/, '') ?? '';
  expect(extid, `org card data-testid "${cardTestId}" carries an extid`).not.toBe('');

  const name = ((await firstCard.getByTestId('org-name').textContent()) ?? '').trim();
  expect(name, `org ${extid} has a display name`).not.toBe('');

  return { extid, name };
}
