// e2e/full/organization-settings.spec.ts

/**
 * E2E Tests for Organization Settings Pages
 *
 * Tests the organization management pages:
 * - /orgs (OrganizationsSettings) - List of all user organizations
 * - /org/:extid/:tab? (OrganizationSettings) - Single organization detail with tabs
 *
 * Key testids verified:
 * - OrganizationsSettings (/orgs):
 *   - organizations-list: Container for org cards
 *   - org-card-{extid}: Individual org card
 *   - org-link-{extid}: Clickable org name button
 *   - org-name: Display name text
 *
 * - OrganizationSettings (/org/:extid/:tab?):
 *   - Tabs, in order: org-tab-domains, org-tab-members, org-tab-sso (only when
 *     ORGS_SSO_ENABLED), org-tab-activity (unless ORGS_AUDIT_LOGS_ENABLED=false),
 *     org-tab-settings (element id org-tab-general, always last)
 *   - Panels: org-section-domains, org-section-members, org-section-sso,
 *     org-section-activity, org-section-settings, and org-section-subscription
 *     (no tab since #2929; reached by /org/:extid/subscription and, with
 *     billing on, the header plan chip)
 *
 * Prerequisites:
 * - Authenticated via the project storageState (e2e/global.setup.ts consumes
 *   TEST_USER_*). That account owns its default organization from signup on,
 *   so every test here asserts the organization instead of skipping without it.
 *
 * Usage:
 *   TEST_USER_EMAIL=user@example.com TEST_USER_PASSWORD=secret \
 *     pnpm test:playwright organization-settings.spec.ts
 */

import { expect, type Page, test } from '@playwright/test';

import { env } from '../support/env';
import { getFirstOrganization } from '../support/organizations';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

interface OrgTab {
  testid: string;
  label: string;
  /** The :tab URL segment that selects it. */
  urlTab: string;
  panel: string;
}

const TABS = {
  domains: {
    testid: 'org-tab-domains',
    label: 'Domains',
    urlTab: 'domains',
    panel: 'org-section-domains',
  },
  members: {
    testid: 'org-tab-members',
    label: 'Members',
    urlTab: 'members',
    panel: 'org-section-members',
  },
  sso: { testid: 'org-tab-sso', label: 'SSO', urlTab: 'sso', panel: 'org-section-sso' },
  activity: {
    testid: 'org-tab-activity',
    label: 'Activity',
    urlTab: 'activity',
    panel: 'org-section-activity',
  },
  settings: {
    testid: 'org-tab-settings',
    label: 'Settings',
    urlTab: 'settings',
    panel: 'org-section-settings',
  },
} satisfies Record<string, OrgTab>;

interface OrgFeatureFlags {
  billingEnabled: boolean;
  /** features.organizations.sso_enabled (ORGS_SSO_ENABLED). */
  ssoEnabled: boolean;
  /** features.organizations.audit_logs_enabled (ORGS_AUDIT_LOGS_ENABLED, default on). */
  auditLogsEnabled: boolean;
}

/**
 * Read the instance flags that decide which org tabs exist, from the same
 * bootstrap payload the SPA reads (src/utils/features.ts).
 */
async function orgFeatureFlags(page: Page): Promise<OrgFeatureFlags> {
  const response = await page.request.get('/bootstrap/me');
  expect(response.ok(), 'GET /bootstrap/me').toBe(true);
  const bootstrap = await response.json();
  const orgs = bootstrap.features?.organizations ?? {};
  return {
    billingEnabled: bootstrap.billing_enabled === true,
    ssoEnabled: orgs.sso_enabled === true,
    auditLogsEnabled: orgs.audit_logs_enabled !== false,
  };
}

/** The tab bar the flags call for, in the designed order (Settings last). */
function designedTabs(flags: OrgFeatureFlags): OrgTab[] {
  return [
    TABS.domains,
    TABS.members,
    ...(flags.ssoEnabled ? [TABS.sso] : []),
    ...(flags.auditLogsEnabled ? [TABS.activity] : []),
    TABS.settings,
  ];
}

function orgTablist(page: Page) {
  return page.getByRole('tablist', { name: 'Organization settings tabs' });
}

/**
 * Open an organization's settings page and wait for its tab bar, which renders
 * only once the organization has loaded.
 */
async function gotoOrgSettings(page: Page, extid: string, urlTab?: string): Promise<void> {
  await page.goto(urlTab ? `/org/${extid}/${urlTab}` : `/org/${extid}`);
  await expect(orgTablist(page)).toBeVisible();
}

function tabUrl(extid: string, tab: OrgTab): RegExp {
  return new RegExp(`/org/${extid}/${tab.urlTab}$`);
}

// -----------------------------------------------------------------------------
// Organizations List Page Tests (/orgs)
// -----------------------------------------------------------------------------

test.describe('ORG-LIST: Organizations List Page (/orgs)', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('ORG-LIST-001: Organizations list renders with correct testids', async ({ page }) => {
    const org = await getFirstOrganization(page);

    const card = page.getByTestId(`org-card-${org.extid}`);
    await expect(card).toBeVisible();
    await expect(card.getByTestId(`org-link-${org.extid}`)).toBeVisible();
    await expect(card.getByTestId('org-name')).toHaveText(org.name);
  });

  test('ORG-LIST-002: Account without an owned organization is redirected from /orgs', async ({
    page,
  }) => {
    // /orgs requires owning an organization (requiresOrgRole: 'owner',
    // handleOrgRoleRequirement): with none, the guard redirects to
    // /dashboard before the page mounts, so the list's empty state never
    // shows. The lane account always owns its default organization, so the
    // list endpoint is stubbed empty to reach that case.
    await page.route('**/api/organizations', async (route) => {
      if (route.request().method() !== 'GET') return route.fallback();
      return route.fulfill({ json: { records: [], count: 0 } });
    });

    await page.goto('/orgs');

    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(page.getByTestId('organizations-list')).toHaveCount(0);
  });

  test('ORG-LIST-003: Navigation to org detail page works', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await page.getByTestId(`org-link-${org.extid}`).click();

    await expect(page).toHaveURL(new RegExp(`/org/${org.extid}$`));
    await expect(page.getByRole('heading', { level: 1, name: org.name })).toBeVisible();
    await expect(orgTablist(page)).toBeVisible();
  });

  test('ORG-LIST-004: Default organization card shows the Default badge', async ({ page }) => {
    const org = await getFirstOrganization(page);

    // The lane account's only organization is the default workspace created
    // at signup. Paid-plan badges (PRO, Early Supporter) need a billing
    // lane and are not asserted here.
    await expect(
      page.getByTestId(`org-card-${org.extid}`).getByText('Default', { exact: true })
    ).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// Organization Detail Page Tests (/org/:extid/:tab?)
// -----------------------------------------------------------------------------

test.describe('ORG-DETAIL: Organization Settings Page (/org/:extid/:tab?)', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('ORG-DETAIL-001: Tab navigation structure renders correctly', async ({ page }) => {
    const flags = await orgFeatureFlags(page);
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    const expected = designedTabs(flags);
    await expect(orgTablist(page).getByRole('tab')).toHaveCount(expected.length);

    for (const tab of expected) {
      const button = page.getByTestId(tab.testid);
      await expect(button).toBeVisible();
      await expect(button).toHaveAttribute('role', 'tab');
    }

    // Roving tabindex: only the selected tab is in the page tab sequence.
    await expect(orgTablist(page).locator('[role="tab"][tabindex="0"]')).toHaveCount(1);
    await expect(page.getByTestId(TABS.domains.testid)).toHaveAttribute('tabindex', '0');

    if (!flags.ssoEnabled) {
      await expect(page.getByTestId(TABS.sso.testid)).toHaveCount(0);
    }
  });

  test('ORG-DETAIL-002: Default tab is domains', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    await expect(page.getByTestId(TABS.domains.testid)).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId(TABS.domains.panel)).toBeVisible();
  });

  test('ORG-DETAIL-003: Domains tab navigation and panel', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid, 'domains');

    await expect(page.getByTestId(TABS.domains.testid)).toHaveAttribute('aria-selected', 'true');

    const domainsPanel = page.getByTestId(TABS.domains.panel);
    await expect(domainsPanel).toBeVisible();
    await expect(domainsPanel).toHaveAttribute('role', 'tabpanel');
    await expect(domainsPanel).toHaveAttribute('aria-labelledby', 'org-tab-domains');

    // The owner gets the add-domain action (canCreateDomain).
    await expect(domainsPanel.getByRole('link', { name: /add domain/i })).toHaveAttribute(
      'href',
      `/org/${org.extid}/domains/add`
    );
  });

  test('ORG-DETAIL-004: Subscription panel opens from its URL', async ({ page }) => {
    // The Subscription tab left the tab bar in #2929; the panel is still
    // reached at /org/:extid/subscription (the header plan chip links there
    // when billing is on).
    const flags = await orgFeatureFlags(page);
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid, 'subscription');

    await expect(page).toHaveURL(new RegExp(`/org/${org.extid}/subscription$`));
    const subscriptionPanel = page.getByTestId('org-section-subscription');
    await expect(subscriptionPanel).toBeVisible();

    const heading = flags.billingEnabled
      ? 'Subscription Status'
      : 'Billing Integration Coming Soon';
    await expect(subscriptionPanel.getByRole('heading', { name: heading })).toBeVisible();

    // With no tab to label it, the view is not a tabpanel but a region named
    // by its heading.
    await expect(subscriptionPanel).not.toHaveAttribute('role', 'tabpanel');
    await expect(page.getByRole('tabpanel')).toHaveCount(0);
    await expect(page.getByRole('region', { name: heading, exact: true })).toHaveAttribute(
      'data-testid',
      'org-section-subscription'
    );
  });

  test('ORG-DETAIL-005: Settings tab navigation and panel', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid, 'settings');

    await expect(page.getByTestId(TABS.settings.testid)).toHaveAttribute('aria-selected', 'true');

    const settingsPanel = page.getByTestId(TABS.settings.panel);
    await expect(settingsPanel).toBeVisible();
    await expect(settingsPanel.locator('input#display-name')).toHaveValue(org.name);
  });

  test('ORG-DETAIL-006: SSO tab opens the SSO panel', async ({ page }) => {
    test.fixme(
      !env.hasSsoUi,
      'Needs org SSO turned on (ORGS_SSO_ENABLED) and the manage_sso entitlement; the ' +
        'full lane configures neither. Set E2E_SSO_UI on such a target. See issue #3420.'
    );

    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    const ssoTab = page.getByTestId(TABS.sso.testid);
    await expect(ssoTab).toBeVisible();
    await expect(ssoTab).not.toHaveAttribute('aria-disabled', 'true');

    await ssoTab.click();

    await expect(ssoTab).toHaveAttribute('aria-selected', 'true');
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.sso));
    await expect(page.getByTestId(TABS.sso.panel)).toBeVisible();
  });

  test('ORG-DETAIL-007: Tab click updates URL', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    for (const tab of [TABS.members, TABS.settings, TABS.domains]) {
      await page.getByTestId(tab.testid).click();
      await expect(page).toHaveURL(tabUrl(org.extid, tab));
      await expect(page.getByTestId(tab.testid)).toHaveAttribute('aria-selected', 'true');
      await expect(page.getByTestId(tab.panel)).toBeVisible();
    }
  });

  test('ORG-DETAIL-008: Back navigation to /orgs works', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    // The header link wraps the page's h1 (the organization name).
    const backLink = page
      .locator('a[href="/orgs"]')
      .filter({ has: page.getByRole('heading', { level: 1 }) });
    await backLink.click();

    await expect(page).toHaveURL(/\/orgs$/);
    await expect(page.getByTestId(`org-card-${org.extid}`)).toBeVisible();
  });

  test('ORG-DETAIL-009: Direct URL navigation to specific tabs works', async ({ page }) => {
    const org = await getFirstOrganization(page);

    for (const tab of [TABS.domains, TABS.members, TABS.settings]) {
      await gotoOrgSettings(page, org.extid, tab.urlTab);
      await expect(page.getByTestId(tab.testid)).toHaveAttribute('aria-selected', 'true');
      await expect(page.getByTestId(tab.panel)).toBeVisible();
    }

    // The legacy /team segment still opens the Members tab.
    await gotoOrgSettings(page, org.extid, 'team');
    await expect(page.getByTestId(TABS.members.testid)).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId(TABS.members.panel)).toBeVisible();
  });

  test('ORG-DETAIL-010: Tab switches replace the history entry; Back restores the last tab', async ({
    page,
  }) => {
    // getFirstOrganization leaves /orgs as the entry before this page.
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid, 'domains');

    // Tab switches rewrite the current entry instead of pushing new ones.
    await page.getByTestId(TABS.members.testid).click();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.members));
    await page.getByTestId(TABS.settings.testid).click();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.settings));

    // Leave through the app (a router push), then come Back: the entry keeps
    // the tab the user left on rather than the one the page loaded with.
    await page
      .locator('a[href="/orgs"]')
      .filter({ has: page.getByRole('heading', { level: 1 }) })
      .click();
    await expect(page).toHaveURL(/\/orgs$/);

    await page.goBack();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.settings));
    await expect(page.getByTestId(TABS.settings.testid)).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId(TABS.settings.panel)).toBeVisible();

    // One more Back skips straight past the tab switches to /orgs.
    await page.goBack();
    await expect(page).toHaveURL(/\/orgs$/);

    await page.goForward();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.settings));
    await expect(page.getByTestId(TABS.settings.testid)).toHaveAttribute('aria-selected', 'true');
  });

  test('ORG-DETAIL-011: Direct and Back/Forward navigation to a gated tab redirect to domains', async ({
    page,
  }) => {
    const org = await getFirstOrganization(page);
    const gatedTab = TABS.sso;

    // The full lane runs without ORGS_SSO_ENABLED, so SSO is a tab this
    // account cannot open: it is absent, or present but aria-disabled.
    await gotoOrgSettings(page, org.extid, 'settings');
    await expect(
      orgTablist(page).locator(`[data-testid="${gatedTab.testid}"]:not([aria-disabled="true"])`)
    ).toHaveCount(0);

    // A typed or bookmarked URL lands on domains, URL included.
    await page.goto(`/org/${org.extid}/${gatedTab.urlTab}`);
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.domains));
    await expect(page.getByTestId(TABS.domains.testid)).toHaveAttribute('aria-selected', 'true');

    // A history entry that names the gated tab (e.g. written while the user
    // still had access) is corrected when Back/Forward returns to it.
    await page.getByTestId(TABS.settings.testid).click();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.settings));
    await page.evaluate((url) => {
      window.history.pushState({}, '', url);
    }, `/org/${org.extid}/${gatedTab.urlTab}`);

    await page.goBack();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.settings));
    await expect(page.getByTestId(TABS.settings.testid)).toHaveAttribute('aria-selected', 'true');

    await page.goForward();
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.domains));
    await expect(page.getByTestId(TABS.domains.testid)).toHaveAttribute('aria-selected', 'true');
  });

  test('ORG-TAB-ORDER-001: Tabs render in correct visual order', async ({ page }) => {
    const flags = await orgFeatureFlags(page);
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    await expect(orgTablist(page).getByRole('tab')).toHaveText(
      designedTabs(flags).map((tab) => tab.label)
    );
  });
});

// -----------------------------------------------------------------------------
// Organization Not Found
// -----------------------------------------------------------------------------

test.describe('ORG-ERROR: Organization Error States', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('ORG-ERROR-001: Invalid org extid redirects away from org settings', async ({ page }) => {
    // /org/:extid requires the admin role on that org. For an unknown extid
    // the org fetch 404s, the role guard fails closed and redirects to
    // /dashboard (src/router/guards.routes.ts, handleOrgRoleRequirement), so
    // the page never renders its own not-found state.
    await page.goto('/org/invalid-org-id-12345');

    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(orgTablist(page)).toHaveCount(0);
    await expect(page.getByTestId(TABS.domains.testid)).toHaveCount(0);
  });
});

// -----------------------------------------------------------------------------
// Keyboard Accessibility
// -----------------------------------------------------------------------------

test.describe('ORG-A11Y: Organization Settings Accessibility', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('ORG-A11Y-001: Tab navigation with keyboard (Arrow keys)', async ({ page }) => {
    const flags = await orgFeatureFlags(page);
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid);

    // Arrow keys move through the tabs the user can open (WAI-ARIA tabs,
    // automatic activation) in tab-bar order, then wrap. A rendered but
    // aria-disabled tab (SSO without manage_sso) is passed over. The owner
    // can always manage members.
    await expect(page.getByTestId(TABS.members.testid)).not.toHaveAttribute(
      'aria-disabled',
      'true'
    );
    const cycle: OrgTab[] = [];
    for (const tab of designedTabs(flags)) {
      if ((await page.getByTestId(tab.testid).getAttribute('aria-disabled')) !== 'true') {
        cycle.push(tab);
      }
    }

    const expectActive = async (tab: OrgTab) => {
      const button = page.getByTestId(tab.testid);
      await expect(button).toBeFocused();
      await expect(button).toHaveAttribute('aria-selected', 'true');
      await expect(button).toHaveAttribute('tabindex', '0');
      await expect(page).toHaveURL(tabUrl(org.extid, tab));
      await expect(page.getByTestId(tab.panel)).toBeVisible();
    };

    await page.getByTestId(TABS.domains.testid).focus();
    await expect(page.getByTestId(TABS.domains.testid)).toBeFocused();

    // ArrowRight walks forward and wraps from the last tab to the first.
    for (let step = 1; step <= cycle.length; step++) {
      await page.keyboard.press('ArrowRight');
      await expectActive(cycle[step % cycle.length]);
    }

    // ArrowLeft walks backward and wraps from the first tab to the last.
    for (let step = cycle.length - 1; step >= 0; step--) {
      await page.keyboard.press('ArrowLeft');
      await expectActive(cycle[step]);
    }

    await page.keyboard.press('End');
    await expectActive(cycle[cycle.length - 1]);
    await page.keyboard.press('Home');
    await expectActive(cycle[0]);
  });

  test('ORG-A11Y-002: Tab panels have correct ARIA attributes', async ({ page }) => {
    const org = await getFirstOrganization(page);

    await gotoOrgSettings(page, org.extid, 'domains');
    await expect(page.getByTestId(TABS.domains.panel)).toHaveAttribute('role', 'tabpanel');

    await gotoOrgSettings(page, org.extid, 'settings');
    const settingsPanel = page.getByTestId(TABS.settings.panel);
    await expect(settingsPanel).toHaveAttribute('role', 'tabpanel');
    await expect(settingsPanel).toHaveAttribute('tabindex', '0');
  });

  test('ORG-A11Y-003: The tab list stays keyboard-reachable on the subscription view', async ({
    page,
  }) => {
    // /org/:extid/subscription has no tab, so no tab is selected. The first
    // tab holds the roving tabindex instead, and the arrow keys move from it.
    const org = await getFirstOrganization(page);
    await gotoOrgSettings(page, org.extid, 'subscription');
    await expect(page.getByTestId('org-section-subscription')).toBeVisible();

    const tablist = orgTablist(page);
    await expect(tablist.locator('[role="tab"][aria-selected="true"]')).toHaveCount(0);
    await expect(tablist.locator('[role="tab"][tabindex="0"]')).toHaveCount(1);
    await expect(page.getByTestId(TABS.domains.testid)).toHaveAttribute('tabindex', '0');

    await page.getByTestId(TABS.domains.testid).focus();
    await page.keyboard.press('ArrowRight');

    const membersTab = page.getByTestId(TABS.members.testid);
    await expect(membersTab).toBeFocused();
    await expect(membersTab).toHaveAttribute('aria-selected', 'true');
    await expect(page).toHaveURL(tabUrl(org.extid, TABS.members));
    await expect(page.getByTestId(TABS.members.panel)).toBeVisible();
    await expect(page.getByTestId('org-section-subscription')).toHaveCount(0);
  });
});

/**
 * Test Case Reference (Qase-compatible)
 *
 * Suite: Organization Settings Pages
 *
 * | ID               | Title                                                    | Priority | Automation |
 * |------------------|----------------------------------------------------------|----------|------------|
 * | ORG-LIST-001     | Organizations list renders with correct testids          | Critical | Automated  |
 * | ORG-LIST-002     | Account without an owned organization is redirected      | Medium   | Automated  |
 * | ORG-LIST-003     | Navigation to org detail page works                      | Critical | Automated  |
 * | ORG-LIST-004     | Default organization card shows the Default badge        | Low      | Automated  |
 * | ORG-DETAIL-001   | Tab navigation structure renders correctly               | Critical | Automated  |
 * | ORG-DETAIL-002   | Default tab is domains                                   | High     | Automated  |
 * | ORG-DETAIL-003   | Domains tab navigation and panel                         | Critical | Automated  |
 * | ORG-DETAIL-004   | Subscription panel opens from its URL                    | High     | Automated  |
 * | ORG-DETAIL-005   | Settings tab navigation and panel                        | High     | Automated  |
 * | ORG-DETAIL-006   | SSO tab opens the SSO panel                              | Medium   | Fixme (#3420, E2E_SSO_UI) |
 * | ORG-DETAIL-007   | Tab click updates URL                                    | Critical | Automated  |
 * | ORG-DETAIL-008   | Back navigation to /orgs works                           | High     | Automated  |
 * | ORG-DETAIL-009   | Direct URL navigation to specific tabs works             | High     | Automated  |
 * | ORG-DETAIL-010   | Tab switches replace the history entry; Back restores it | Medium   | Automated  |
 * | ORG-DETAIL-011   | Direct and Back/Forward navigation to gated tab redirect | High     | Automated  |
 * | ORG-TAB-ORDER-001| Tabs render in correct visual order                      | High     | Automated  |
 * | ORG-ERROR-001    | Invalid org extid redirects away from org settings       | High     | Automated  |
 * | ORG-A11Y-001     | Tab navigation with keyboard (Arrow keys)                | Medium   | Automated  |
 * | ORG-A11Y-002     | Tab panels have correct ARIA attributes                  | Medium   | Automated  |
 * | ORG-A11Y-003     | Tab list keyboard-reachable on the subscription view     | Medium   | Automated  |
 */
