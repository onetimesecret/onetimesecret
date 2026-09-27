// e2e/full/org-switcher-navigation.spec.ts

//
// Regression tests for switching workspace on the organization settings pages.
//
// The bug: on /org/{extid}/{tab}, choosing another workspace in the header
// switcher updated the header but left the URL and the page content on the
// old workspace. The fix: the /org/:extid/:tab? route declares
// `onOrgSwitch: 'same'` (src/apps/workspace/routes/organizations.ts), so a
// switch navigates to the same tab of the chosen workspace.
//
// Runs as a throwaway owner of two workspaces (e2e/support/workspaces.ts):
// the storageState account owns one solo default workspace, for which the
// switcher is hidden. Needs ENABLE_ORGS=true on the target (full lane).

import type { Page } from '@playwright/test';

import type { CreatedOrganization } from '../support/members';
import { expect, test } from '../support/workspaces';

const orgSwitcher = {
  trigger: (page: Page) => page.getByTestId('org-scope-switcher-trigger'),
  dropdown: (page: Page) => page.getByTestId('org-scope-switcher-dropdown'),
  row: (page: Page, extid: string) => page.getByTestId(`org-menu-item-${extid}`),
};

/** Open a tab of a workspace's settings and wait for the switcher to name it. */
async function gotoOrgTab(page: Page, workspace: CreatedOrganization, tab: string): Promise<void> {
  await page.goto(`/org/${workspace.extid}/${tab}`);
  await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', workspace.name);
}

/** Choose a workspace in the switcher and wait for the dropdown to close. */
async function switchTo(page: Page, workspace: CreatedOrganization): Promise<void> {
  await orgSwitcher.trigger(page).click();
  await expect(orgSwitcher.dropdown(page)).toBeVisible();
  await orgSwitcher.row(page, workspace.extid).click();
  await expect(orgSwitcher.dropdown(page)).toBeHidden();
}

/** The settings page names its workspace in the page heading. */
function workspaceHeading(page: Page, workspace: CreatedOrganization) {
  return page.getByRole('heading', { level: 1, name: workspace.name });
}

test.describe('Org Switcher Navigation - Same Tab Navigation', () => {
  test('TC-OSN-001: Switching on the Domains tab opens the other workspace Domains tab', async ({
    ownerPage: page,
    owner,
  }) => {
    const from = owner.defaultWorkspace;
    const to = owner.secondWorkspace;
    await gotoOrgTab(page, from, 'domains');
    await expect(workspaceHeading(page, from)).toBeVisible();

    await switchTo(page, to);

    await expect(page).toHaveURL(new RegExp(`/org/${to.extid}/domains$`));
    await expect(workspaceHeading(page, to)).toBeVisible();
    await expect(page.getByTestId('org-section-domains')).toBeVisible();
  });

  test('TC-OSN-002: Switching on the Subscription tab keeps the tab', async ({
    ownerPage: page,
    owner,
  }) => {
    // The Billing tab is now Subscription (/billing still aliases to it)
    const from = owner.defaultWorkspace;
    const to = owner.secondWorkspace;
    await gotoOrgTab(page, from, 'subscription');
    await expect(page.getByTestId('org-section-subscription')).toBeVisible();

    await switchTo(page, to);

    await expect(page).toHaveURL(new RegExp(`/org/${to.extid}/subscription$`));
    await expect(workspaceHeading(page, to)).toBeVisible();
    await expect(page.getByTestId('org-section-subscription')).toBeVisible();
  });

  test('TC-OSN-003: Switching on the Settings tab shows the other workspace settings', async ({
    ownerPage: page,
    owner,
  }) => {
    const from = owner.defaultWorkspace;
    const to = owner.secondWorkspace;
    await gotoOrgTab(page, from, 'settings');
    const displayName = page.getByTestId('org-section-settings').locator('input#display-name');
    await expect(displayName).toHaveValue(from.name);

    await switchTo(page, to);

    await expect(page).toHaveURL(new RegExp(`/org/${to.extid}/settings$`));
    await expect(displayName).toHaveValue(to.name);
  });

  test('TC-OSN-004: Switching there and back returns to the first workspace', async ({
    ownerPage: page,
    owner,
  }) => {
    const first = owner.defaultWorkspace;
    const second = owner.secondWorkspace;
    await gotoOrgTab(page, first, 'domains');

    await switchTo(page, second);
    await expect(page).toHaveURL(new RegExp(`/org/${second.extid}/domains$`));
    await expect(workspaceHeading(page, second)).toBeVisible();

    await switchTo(page, first);
    await expect(page).toHaveURL(new RegExp(`/org/${first.extid}/domains$`));
    await expect(workspaceHeading(page, first)).toBeVisible();
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', first.name);
  });

  test('TC-OSN-005: The header, URL and page agree after a switch', async ({
    ownerPage: page,
    owner,
  }) => {
    const from = owner.defaultWorkspace;
    const to = owner.secondWorkspace;
    await gotoOrgTab(page, from, 'domains');

    await switchTo(page, to);

    // The bug: the header changed while the URL and content stayed behind
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', to.name);
    await expect(orgSwitcher.trigger(page)).toContainText(to.name);
    await expect(page).toHaveURL(new RegExp(`/org/${to.extid}/`));
    await expect(workspaceHeading(page, to)).toBeVisible();
    await expect(workspaceHeading(page, from)).toHaveCount(0);
  });

  test('TC-OSN-006: Switching after a tab click keeps the tab on screen', async ({
    ownerPage: page,
    owner,
  }) => {
    // The 'same' target is built from the router's current route. A tab click
    // must move that route to the clicked tab, or the switch lands on the tab
    // the page was opened with.
    const from = owner.defaultWorkspace;
    const to = owner.secondWorkspace;
    await gotoOrgTab(page, from, 'domains');
    await page.getByTestId('org-tab-settings').click();
    await expect(page).toHaveURL(new RegExp(`/org/${from.extid}/settings$`));
    const displayName = page.getByTestId('org-section-settings').locator('input#display-name');
    await expect(displayName).toHaveValue(from.name);

    await switchTo(page, to);

    await expect(page).toHaveURL(new RegExp(`/org/${to.extid}/settings$`));
    await expect(displayName).toHaveValue(to.name);
    await expect(page.getByTestId('org-tab-settings')).toHaveAttribute('aria-selected', 'true');
  });
});

test.describe('Org Switcher Navigation - Edge Cases', () => {
  test('TC-OSN-010: Selecting the current workspace does not navigate', async ({
    ownerPage: page,
    owner,
  }) => {
    const current = owner.defaultWorkspace;
    const other = owner.secondWorkspace;
    await gotoOrgTab(page, current, 'domains');
    const historyLength = await page.evaluate(() => window.history.length);

    await switchTo(page, current);

    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', current.name);
    await expect(workspaceHeading(page, current)).toBeVisible();

    // A URL check right after the selection cannot see a navigation that has
    // not finished yet, so the test makes a later switch and reads what is
    // left: a push from the selection shows as an extra history entry, a
    // replace to another tab as the tab the switch keeps. This sees only a
    // navigation that finished before the later switch started. Vue Router
    // does not queue navigations: starting one cancels any still pending, so
    // a selection whose navigation waited on a slow guard would be cancelled
    // here and the test would still pass. Today the selection pushes the
    // route already on screen, which Vue Router settles at once as a
    // duplicate without running guards.
    await switchTo(page, other);
    await expect(page).toHaveURL(new RegExp(`/org/${other.extid}/domains$`));
    expect(await page.evaluate(() => window.history.length)).toBe(historyLength + 1);
  });

  test('TC-OSN-011: Back after a switch returns to the previous workspace', async ({
    ownerPage: page,
    owner,
  }) => {
    const from = owner.defaultWorkspace;
    const to = owner.secondWorkspace;
    await gotoOrgTab(page, from, 'domains');
    await switchTo(page, to);
    await expect(page).toHaveURL(new RegExp(`/org/${to.extid}/domains$`));

    await page.goBack();

    await expect(page).toHaveURL(new RegExp(`/org/${from.extid}/domains$`));
    await expect(workspaceHeading(page, from)).toBeVisible();
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', from.name);
  });

  test('TC-OSN-012: A link to the tab on screen adds no history entry', async ({
    ownerPage: page,
    owner,
  }) => {
    // The user menu's Activity item links /org/<current>/activity. After a
    // tab click has put Activity on screen, following it is a duplicate
    // navigation. If the router still held the tab the page was opened with,
    // the link would push a second /activity entry and remount the page.
    const current = owner.defaultWorkspace;
    const other = owner.secondWorkspace;
    await gotoOrgTab(page, current, 'domains');
    await page.getByTestId('org-tab-activity').click();
    await expect(page).toHaveURL(new RegExp(`/org/${current.extid}/activity$`));
    await expect(page.getByTestId('org-section-activity')).toBeVisible();
    const historyLength = await page.evaluate(() => window.history.length);

    await page.getByTestId('user-menu-trigger').click();
    await page
      .getByTestId('user-menu-dropdown')
      .getByRole('menuitem', { name: 'Activity', exact: true })
      .click();
    await expect(page.getByTestId('user-menu-dropdown')).toBeHidden();
    await expect(page).toHaveURL(new RegExp(`/org/${current.extid}/activity$`));
    await expect(page.getByTestId('org-section-activity')).toBeVisible();

    // Leave through the switcher: once that navigation has landed, a push
    // from the menu item shows as an extra history entry.
    await switchTo(page, other);
    await expect(page).toHaveURL(new RegExp(`/org/${other.extid}/activity$`));
    expect(await page.evaluate(() => window.history.length)).toBe(historyLength + 1);
  });

  test('TC-OSN-013: The user menu marks its Activity item current only on the Activity tab', async ({
    ownerPage: page,
    owner,
  }) => {
    // RouterLink sets aria-current="page" from the router's current route. A
    // tab switch must move that route, or the Activity item keeps the mark
    // after the user leaves the Activity tab (and never gets it back).
    const current = owner.defaultWorkspace;
    const menuTrigger = page.getByTestId('user-menu-trigger');
    const menu = page.getByTestId('user-menu-dropdown');
    const activityItem = menu.getByRole('menuitem', { name: 'Activity', exact: true });
    const closeMenu = async () => {
      await menuTrigger.click();
      await expect(menu).toBeHidden();
    };

    await gotoOrgTab(page, current, 'activity');
    await menuTrigger.click();
    await expect(activityItem).toHaveAttribute('aria-current', 'page');
    await closeMenu();

    await page.getByTestId('org-tab-domains').click();
    await expect(page).toHaveURL(new RegExp(`/org/${current.extid}/domains$`));
    await menuTrigger.click();
    await expect(activityItem).toBeVisible();
    await expect(activityItem).not.toHaveAttribute('aria-current');
    await closeMenu();

    await page.getByTestId('org-tab-activity').click();
    await expect(page).toHaveURL(new RegExp(`/org/${current.extid}/activity$`));
    await menuTrigger.click();
    await expect(activityItem).toHaveAttribute('aria-current', 'page');
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Org Switcher Navigation Fix
 *
 * | ID          | Title                                                    | Priority | Automation |
 * |-------------|----------------------------------------------------------|---------:|------------|
 * | TC-OSN-001  | Switching keeps the Domains tab                          | Critical | Automated  |
 * | TC-OSN-002  | Switching keeps the Subscription (was Billing) tab       | High     | Automated  |
 * | TC-OSN-003  | Switching keeps the Settings tab                         | High     | Automated  |
 * | TC-OSN-004  | Switching there and back                                 | Critical | Automated  |
 * | TC-OSN-005  | Header, URL and page agree after a switch                | Critical | Automated  |
 * | TC-OSN-006  | Switching after a tab click keeps the tab on screen      | High     | Automated  |
 * | TC-OSN-010  | Selecting the current workspace does not navigate        | Medium   | Automated  |
 * | TC-OSN-011  | Back returns to the previous workspace                   | Medium   | Automated  |
 * | TC-OSN-012  | A link to the tab on screen adds no history entry        | Medium   | Automated  |
 * | TC-OSN-013  | The user menu marks Activity current only on that tab    | Medium   | Automated  |
 *
 * Bug Reference:
 * - Issue: Org switcher on /org/{extid}/* pages updated header but not URL/content
 * - Root Cause: Missing onOrgSwitch navigation behavior in route meta
 * - Fix: Added `onOrgSwitch: 'same'` to /org/:extid/:tab? route
 * - File: src/apps/workspace/routes/organizations.ts
 */
