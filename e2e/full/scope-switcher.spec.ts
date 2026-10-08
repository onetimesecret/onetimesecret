// e2e/full/scope-switcher.spec.ts

//
// E2E tests for the workspace (organization) and domain scope switchers in the
// signed-in header (OrganizationContextBar).
//
// What decides whether a switcher renders:
//   - Route meta `scopesAvailable` (src/types/router.ts SCOPE_PRESETS):
//     'show', 'locked' (visible, disabled) or 'hide'. Examples: /dashboard
//     and /recent show both; /org/:extid/:tab? shows the org switcher and
//     hides the domain one (switching keeps the page: onOrgSwitch 'same');
//     /receipt/:id locks both; /account and its settings pages hide both.
//   - Org switcher (src/shared/composables/useScopeSwitcherVisibility.ts):
//     ENABLE_ORGS (features.organizations.enabled), the user owns the current
//     org or another of their orgs, not a custom-domain host, and not the
//     "solo default" context (exactly one org, the auto-created default, free
//     plan, one member).
//   - Domain switcher: domains enabled on the server (useDomainContext
//     isContextActive).
//
// What the full lane provides (.github/workflows/e2e.yml, full lane):
//   - ENABLE_ORGS=true; domains and billing are off.
//   - The storageState account (e2e/global.setup.ts) owns only its default
//     workspace and is its only member, so the org switcher is hidden for it
//     by the solo rule. TC-SS-050 asserts exactly that.
//   - The visible and interactive cases run as a throwaway owner of two
//     workspaces (e2e/support/workspaces.ts), created once per worker.
//   - No custom domains. The domain-switcher cases run only when the target
//     has one (E2E_CUSTOM_DOMAINS, e2e/support/env.ts); otherwise they are
//     test.fixme and tracked in e2e/QUARANTINE.md (#3420). TC-SS-051 checks
//     the lane's side of that rule: no domain switcher while domains are off.
//
// Test IDs follow the Qase table at the end of this file.

import type { Locator, Page } from '@playwright/test';

import { env } from '../support/env';
import type { CreatedOrganization } from '../support/members';
import { getFirstOrganization } from '../support/organizations';
import { expect, otherWorkspace, test, type WorkspaceOwner } from '../support/workspaces';

// -----------------------------------------------------------------------------
// Locators
// -----------------------------------------------------------------------------

const orgSwitcher = {
  trigger: (page: Page) => page.getByTestId('org-scope-switcher-trigger'),
  dropdown: (page: Page) => page.getByTestId('org-scope-switcher-dropdown'),
  row: (page: Page, extid: string) => page.getByTestId(`org-menu-item-${extid}`),
  manageLink: (page: Page) => page.getByTestId('org-scope-manage-link'),
  /** The name-only chip shown instead of the switcher to admins and members. */
  staticChip: (page: Page) => page.getByTestId('org-context-static'),
};

const domainSwitcher = {
  trigger: (page: Page) => page.getByTestId('domain-context-switcher-trigger'),
  dropdown: (page: Page) => page.getByTestId('domain-context-switcher-dropdown'),
  addIcon: (page: Page) => page.getByTestId('domain-context-add-icon'),
};

const userMenu = {
  trigger: (page: Page) => page.getByTestId('user-menu-trigger'),
  dropdown: (page: Page) => page.getByTestId('user-menu-dropdown'),
  item: (page: Page, name: string) =>
    page.getByTestId('user-menu-dropdown').getByRole('menuitem', { name, exact: true }),
};

/** The settings tab bar on /account and its settings pages. */
function settingsTab(page: Page, name: string): Locator {
  return page
    .getByRole('navigation', { name: 'Settings navigation' })
    .getByRole('link', { name, exact: true });
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/** Wait for the org switcher to finish loading and return the workspace it names. */
async function currentWorkspace(page: Page, owner: WorkspaceOwner): Promise<CreatedOrganization> {
  const trigger = orgSwitcher.trigger(page);
  await expect(trigger).toBeVisible();
  const title = await trigger.getAttribute('title');
  const current = [owner.defaultWorkspace, owner.secondWorkspace].find((w) => w.name === title);
  expect(
    current,
    `the switcher names one of the owner's workspaces (title "${title}")`
  ).toBeTruthy();
  return current!;
}

/**
 * The workspace a locked trigger shows. Its title is the locked message, so
 * read the name from the text instead.
 */
async function currentWorkspaceName(page: Page, owner: WorkspaceOwner): Promise<string> {
  const text = ((await orgSwitcher.trigger(page).textContent()) ?? '').trim();
  const match = [owner.defaultWorkspace, owner.secondWorkspace].find((w) => text.endsWith(w.name));
  expect(match, `the locked switcher names one of the owner's workspaces ("${text}")`).toBeTruthy();
  return match!.name;
}

/** Choose a workspace from the open-able switcher and wait for the menu to close. */
async function selectWorkspace(page: Page, workspace: CreatedOrganization): Promise<void> {
  await orgSwitcher.trigger(page).click();
  await expect(orgSwitcher.dropdown(page)).toBeVisible();
  await orgSwitcher.row(page, workspace.extid).click();
  await expect(orgSwitcher.dropdown(page)).toBeHidden();
}

/**
 * Click a row's settings gear. The gear is display:none until the row is
 * hovered (group-hover), so a locator click fails whenever its
 * scroll-into-view step moves the row out from under the pointer. Hover the
 * row, wait for the gear, then click at its position with the mouse, which
 * does not scroll.
 */
async function clickRowGear(page: Page, row: Locator, label: string): Promise<void> {
  await row.hover();
  const gear = row.getByRole('button', { name: label });
  await expect(gear).toBeVisible();
  const box = await gear.boundingBox();
  expect(box, `the ${label} gear has a position`).not.toBeNull();
  await page.mouse.click(box!.x + box!.width / 2, box!.y + box!.height / 2);
}

/** Open a user-menu entry. Navigates inside the SPA, without a page load. */
async function openFromUserMenu(page: Page, item: string): Promise<void> {
  await userMenu.trigger(page).click();
  await expect(userMenu.dropdown(page)).toBeVisible();
  await userMenu.item(page, item).click();
}

/**
 * Load the dashboard, wait for the org switcher, then open /account through
 * the user menu. The switcher proves the organization list had loaded before
 * the in-app navigation, so its absence afterwards comes from the route.
 */
async function openAccountFromDashboard(page: Page): Promise<void> {
  await page.goto('/dashboard');
  await expect(orgSwitcher.trigger(page)).toBeVisible();
  await openFromUserMenu(page, 'Account');
  await expect(page).toHaveURL(/\/account$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
}

/** Server-side feature flags from the bootstrap payload of the page's session. */
async function bootstrapFlags(
  page: Page
): Promise<{ orgSwitcherEnabled: boolean; domainsEnabled: boolean }> {
  const response = await page.request.get('/bootstrap/me');
  expect(response.ok(), 'GET /bootstrap/me').toBe(true);
  const data = (await response.json()) as {
    domains_enabled?: boolean;
    features?: { organizations?: { enabled?: boolean } };
  };
  return {
    orgSwitcherEnabled: data.features?.organizations?.enabled === true,
    domainsEnabled: data.domains_enabled === true,
  };
}

/**
 * The workspace the server names as current for the page's session. A page
 * load sends no O-Organization-ID header and neither does this request, so
 * the answer is what the server session remembers (#4565).
 */
async function serverWorkspaceExtid(page: Page): Promise<string | undefined> {
  const response = await page.request.get('/bootstrap/me');
  expect(response.ok(), 'GET /bootstrap/me').toBe(true);
  const data = (await response.json()) as { organization?: { extid?: string } };
  return data.organization?.extid;
}

/** The switcher's write of a selection to the server session. */
function workspaceSelectionSaved(page: Page) {
  return page.waitForResponse(
    (response) =>
      response.request().method() === 'POST' &&
      new URL(response.url()).pathname === '/api/account/update-organization-context'
  );
}

// -----------------------------------------------------------------------------
// The lane account: a solo default workspace
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - solo default workspace', () => {
  test('TC-SS-050: a solo default-workspace owner sees no org switcher', async ({ page }) => {
    const orgList = page.waitForResponse(
      (response) =>
        response.request().method() === 'GET' &&
        new URL(response.url()).pathname === '/api/organizations'
    );
    await page.goto('/dashboard');

    // The inputs of the solo rule, as the SPA receives them. The shared
    // account must stay solo: e2e/support/members.ts never adds it anywhere.
    const response = await orgList;
    expect(response.ok(), 'GET /api/organizations').toBe(true);
    const { records } = (await response.json()) as {
      records: { is_default: boolean; planid: string; member_count: number }[];
    };
    expect(records, 'the lane account owns exactly one workspace').toHaveLength(1);
    expect(records[0].is_default).toBe(true);
    expect(records[0].member_count).toBe(1);
    expect(records[0].planid).toMatch(/^free_v\d+$/);

    // With the switcher feature on, only the solo rule can hide it here.
    expect(
      (await bootstrapFlags(page)).orgSwitcherEnabled,
      'the target runs with ENABLE_ORGS=true (full lane in .github/workflows/e2e.yml)'
    ).toBe(true);

    // The user-menu role badge follows the same rule. Opening the menu is a
    // positive signal that the page is interactive after the list loaded.
    await userMenu.trigger(page).click();
    await expect(userMenu.dropdown(page)).toBeVisible();
    await expect(page.getByTestId('user-menu-role-badge')).toHaveCount(0);
    await expect(orgSwitcher.trigger(page)).toHaveCount(0);
    await expect(orgSwitcher.staticChip(page)).toHaveCount(0);
  });
});

// -----------------------------------------------------------------------------
// Visibility per route, as an owner of two workspaces
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - visibility rules', () => {
  test('TC-SS-001: Dashboard shows the org switcher, enabled', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');

    const trigger = orgSwitcher.trigger(page);
    await expect(trigger).toBeVisible();
    await expect(trigger).toBeEnabled();
    await expect(trigger).not.toHaveAttribute('aria-disabled', 'true');
    const current = await currentWorkspace(page, owner);
    await expect(trigger).toContainText(current.name);
  });

  test('TC-SS-003: / takes a signed-in owner to the dashboard secret form, with the org switcher', async ({
    ownerPage: page,
  }) => {
    await page.goto('/');

    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(page.getByRole('textbox', { name: 'Secret content' })).toBeVisible();
    await expect(orgSwitcher.trigger(page)).toBeEnabled();
  });

  test('TC-SS-005: Organization settings: switching opens the other workspace settings', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto(`/org/${owner.defaultWorkspace.extid}`);

    // The route names the workspace, so the switcher shows it.
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', owner.defaultWorkspace.name);
    await expect(orgSwitcher.trigger(page)).toBeEnabled();

    await selectWorkspace(page, owner.secondWorkspace);

    // onOrgSwitch 'same': same page, other workspace
    await expect(page).toHaveURL(new RegExp(`/org/${owner.secondWorkspace.extid}$`));
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', owner.secondWorkspace.name);
  });

  test('TC-SS-007: /domains opens the current workspace Domains tab; switching keeps the tab', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/domains');

    await expect(page).toHaveURL(/\/org\/[^/]+\/domains$/);
    const current = await currentWorkspace(page, owner);
    await expect(page).toHaveURL(new RegExp(`/org/${current.extid}/domains$`));

    const other = otherWorkspace(owner, current);
    await selectWorkspace(page, other);

    await expect(page).toHaveURL(new RegExp(`/org/${other.extid}/domains$`));
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', other.name);
  });

  test('TC-SS-015: Account page hides the org switcher; the dashboard shows it again', async ({
    ownerPage: page,
  }) => {
    await openAccountFromDashboard(page);
    await expect(orgSwitcher.trigger(page)).toHaveCount(0);
    await expect(orgSwitcher.staticChip(page)).toHaveCount(0);

    await page.getByRole('link', { name: 'Back to Dashboard' }).click();
    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(orgSwitcher.trigger(page)).toBeVisible();
  });

  test('TC-SS-017: Profile settings hide the org switcher', async ({ ownerPage: page }) => {
    await openAccountFromDashboard(page);

    await settingsTab(page, 'Profile').click();
    await expect(page).toHaveURL(/\/account\/settings\/profile(\/preferences)?$/);
    await expect(settingsTab(page, 'Profile')).toHaveAttribute('aria-current', 'page');
    await expect(orgSwitcher.trigger(page)).toHaveCount(0);
  });

  test('TC-SS-018: Security settings hide the org switcher', async ({ ownerPage: page }) => {
    await openAccountFromDashboard(page);

    await settingsTab(page, 'Security').click();
    await expect(page).toHaveURL(/\/account\/settings\/security$/);
    await expect(settingsTab(page, 'Security')).toHaveAttribute('aria-current', 'page');
    await expect(orgSwitcher.trigger(page)).toHaveCount(0);
  });
});

// -----------------------------------------------------------------------------
// Switching behavior
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - switching behavior', () => {
  test('TC-SS-020: Clicking the org switcher opens its dropdown', async ({ ownerPage: page }) => {
    await page.goto('/dashboard');
    const trigger = orgSwitcher.trigger(page);
    await expect(trigger).toHaveAttribute('aria-expanded', 'false');

    await trigger.click();

    await expect(orgSwitcher.dropdown(page)).toBeVisible();
    await expect(trigger).toHaveAttribute('aria-expanded', 'true');
  });

  test('TC-SS-021: The dropdown lists both workspaces and marks the current one', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');
    const current = await currentWorkspace(page, owner);
    const other = otherWorkspace(owner, current);

    await orgSwitcher.trigger(page).click();

    await expect(orgSwitcher.row(page, current.extid)).toContainText(current.name);
    await expect(orgSwitcher.row(page, other.extid)).toContainText(other.name);
    await expect(orgSwitcher.row(page, current.extid)).toHaveAttribute('aria-current', 'true');
    await expect(orgSwitcher.row(page, other.extid)).not.toHaveAttribute('aria-current', 'true');
  });

  test('TC-SS-022: Selecting the other workspace makes it current', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');
    const current = await currentWorkspace(page, owner);
    const other = otherWorkspace(owner, current);

    await selectWorkspace(page, other);

    // The dashboard has no onOrgSwitch target: the page stays, the scope moves.
    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', other.name);
    await expect(orgSwitcher.trigger(page)).toContainText(other.name);
    // The server session holds the selection; the write is fire-and-forget
    await expect.poll(() => serverWorkspaceExtid(page)).toBe(other.extid);
    // and it is the only copy: the tab keeps no selection in sessionStorage
    expect(await page.evaluate(() => sessionStorage.getItem('selectedOrganizationId'))).toBeNull();
  });

  test('TC-SS-023: The row gear opens that workspace settings and closes the dropdown', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');
    const current = await currentWorkspace(page, owner);
    const other = otherWorkspace(owner, current);

    await orgSwitcher.trigger(page).click();
    const row = orgSwitcher.row(page, other.extid);
    await clickRowGear(page, row, 'Organization Settings');

    await expect(page).toHaveURL(new RegExp(`/org/${other.extid}$`));
    await expect(orgSwitcher.dropdown(page)).toBeHidden();
  });

  test('TC-SS-024: Manage Workspaces opens /orgs', async ({ ownerPage: page }) => {
    await page.goto('/dashboard');
    await orgSwitcher.trigger(page).click();

    await orgSwitcher.manageLink(page).click();

    await expect(page).toHaveURL(/\/orgs$/);
    // The workspace list page hides both switchers
    await expect(page.getByTestId('organizations-list')).toBeVisible();
    await expect(orgSwitcher.trigger(page)).toHaveCount(0);
  });

  test('TC-SS-060: The selected workspace carries into in-app navigation', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');
    const current = await currentWorkspace(page, owner);
    const other = otherWorkspace(owner, current);
    await selectWorkspace(page, other);

    // /domains resolves against the current workspace
    await openFromUserMenu(page, 'Domains');

    await expect(page).toHaveURL(new RegExp(`/org/${other.extid}/domains$`));
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', other.name);
  });

  test('TC-SS-063: The selected workspace survives a page reload', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');
    const current = await currentWorkspace(page, owner);
    const other = otherWorkspace(owner, current);

    // Wait for the server write, or the reload could overtake it
    const saved = workspaceSelectionSaved(page);
    await selectWorkspace(page, other);
    expect((await saved).ok(), 'POST /api/account/update-organization-context').toBe(true);
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', other.name);

    await page.reload();
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', other.name);
    await expect(orgSwitcher.trigger(page)).toContainText(other.name);

    // A fresh page load of a route that names no workspace
    await page.goto('/dashboard');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('title', other.name);

    // The server names it without being told which workspace the tab holds
    expect(await serverWorkspaceExtid(page)).toBe(other.extid);
  });
});

// -----------------------------------------------------------------------------
// Locked state: receipt pages lock both switchers
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - locked state', () => {
  test('TC-SS-040: A receipt page shows the current workspace in a disabled switcher', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto(owner.receiptPath);

    const trigger = orgSwitcher.trigger(page);
    await expect(trigger).toBeVisible();
    await expect(trigger).toBeDisabled();
    const title = await currentWorkspaceName(page, owner);
    await expect(trigger).toContainText(title);
  });

  test('TC-SS-041: The locked switcher is marked disabled for assistive tech', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto(owner.receiptPath);

    const trigger = orgSwitcher.trigger(page);
    await expect(trigger).toHaveAttribute('aria-disabled', 'true');
    await expect(trigger).toHaveAttribute(
      'title',
      'Workspace switching not available on this page'
    );
    // The lock icon replaces the chevron; the name stays the switcher's
    await expect(trigger).toHaveAccessibleName('Select a workspace');
  });
});

// -----------------------------------------------------------------------------
// Keyboard and ARIA
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - keyboard and accessibility', () => {
  test('TC-SS-053: Enter opens the dropdown, arrows move, Escape closes and refocuses', async ({
    ownerPage: page,
  }) => {
    await page.goto('/dashboard');
    const trigger = orgSwitcher.trigger(page);
    const dropdown = orgSwitcher.dropdown(page);
    await expect(trigger).toBeVisible();

    await trigger.focus();
    await page.keyboard.press('Enter');

    await expect(dropdown).toBeVisible();
    await expect(dropdown).toBeFocused();
    const itemIds = await dropdown
      .getByRole('menuitem')
      .evaluateAll((items) => items.map((item) => item.id));
    expect(itemIds.length, 'two workspace rows and the Manage link').toBe(3);
    await expect(dropdown).toHaveAttribute('aria-activedescendant', itemIds[0]);

    await page.keyboard.press('ArrowDown');
    await expect(dropdown).toHaveAttribute('aria-activedescendant', itemIds[1]);

    await page.keyboard.press('Escape');
    await expect(dropdown).toBeHidden();
    await expect(trigger).toBeFocused();
  });

  test('TC-SS-070: The org switcher trigger has an accessible name', async ({
    ownerPage: page,
  }) => {
    await page.goto('/dashboard');

    await expect(orgSwitcher.trigger(page)).toHaveAccessibleName('Select a workspace');
    await expect(orgSwitcher.trigger(page)).toHaveAttribute('aria-haspopup', 'menu');
  });

  test('TC-SS-072: The dropdown is a menu labelled by its trigger', async ({ ownerPage: page }) => {
    await page.goto('/dashboard');
    const trigger = orgSwitcher.trigger(page);
    await trigger.click();

    const dropdown = orgSwitcher.dropdown(page);
    await expect(dropdown).toHaveAttribute('role', 'menu');
    const triggerId = await trigger.getAttribute('id');
    expect(triggerId, 'the trigger has an id to be labelled by').toBeTruthy();
    await expect(dropdown).toHaveAttribute('aria-labelledby', triggerId!);
  });

  test('TC-SS-073: Workspace rows and the Manage link are menu items', async ({
    ownerPage: page,
    owner,
  }) => {
    await page.goto('/dashboard');
    await orgSwitcher.trigger(page).click();

    const items = orgSwitcher.dropdown(page).getByRole('menuitem');
    await expect(items).toHaveCount(3);
    await expect(orgSwitcher.row(page, owner.defaultWorkspace.extid)).toHaveAttribute(
      'role',
      'menuitem'
    );
    await expect(orgSwitcher.row(page, owner.secondWorkspace.extid)).toHaveAttribute(
      'role',
      'menuitem'
    );
    await expect(orgSwitcher.manageLink(page)).toHaveAttribute('role', 'menuitem');
  });

  test('TC-SS-074: Tab closes the open dropdown', async ({ ownerPage: page }) => {
    await page.goto('/dashboard');
    const trigger = orgSwitcher.trigger(page);
    await expect(trigger).toBeVisible();
    await trigger.focus();
    await page.keyboard.press('Enter');
    await expect(orgSwitcher.dropdown(page)).toBeFocused();

    // A HeadlessUI Menu does not trap focus: Tab closes it and moves on.
    await page.keyboard.press('Tab');

    await expect(orgSwitcher.dropdown(page)).toBeHidden();
    await expect(trigger).toHaveAttribute('aria-expanded', 'false');
  });
});

// -----------------------------------------------------------------------------
// Domain switcher
// -----------------------------------------------------------------------------

test.describe('Scope Switcher - domain switcher, lane state', () => {
  test('TC-SS-051: The domain switcher renders exactly when domains are enabled', async ({
    ownerPage: page,
  }) => {
    await page.goto('/dashboard');
    // The org switcher is the positive signal that the context bar rendered
    // with its data; the domain switcher sits in the same template.
    await expect(orgSwitcher.trigger(page)).toBeVisible();

    const { domainsEnabled } = await bootstrapFlags(page);
    await expect(domainSwitcher.trigger(page)).toHaveCount(domainsEnabled ? 1 : 0);
  });
});

/**
 * The domain-switcher cases need a custom domain on the storageState account
 * on a target with domains enabled. E2E_CUSTOM_DOMAINS must list the domain
 * names (the first is used), not just a truthy value. No CI lane provides one
 * yet (#3420). They run as that account, whose org switcher is hidden by the
 * solo rule, so they drive the domain switcher only.
 */
test.describe('Scope Switcher - domain switcher with custom domains', () => {
  test.fixme(
    !env.hasCustomDomains,
    'Needs a custom domain on the test account (E2E_CUSTOM_DOMAINS); no lane provisions one. See #3420.'
  );

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  /** A custom domain the target serves for the test account. */
  const customDomain = () => env.customDomains[0];

  test('TC-SS-002: Dashboard shows the domain switcher, enabled', async ({ page }) => {
    await page.goto('/dashboard');

    await expect(domainSwitcher.trigger(page)).toBeVisible();
    await expect(domainSwitcher.trigger(page)).toBeEnabled();
  });

  test('TC-SS-006: Organization settings hide the domain switcher', async ({ page }) => {
    const org = await getFirstOrganization(page);
    // Load the dashboard first: its domain switcher proves the domain context
    // is active before the in-app navigation to a page that hides it.
    await page.goto('/dashboard');
    await expect(domainSwitcher.trigger(page)).toBeVisible();

    // Activity is a tab of the organization settings route (/org/:extid/:tab?)
    await openFromUserMenu(page, 'Activity');

    await expect(page).toHaveURL(new RegExp(`/org/${org.extid}/activity$`));
    await expect(domainSwitcher.trigger(page)).toHaveCount(0);
  });

  test('TC-SS-008: The Domains tab (/domains) hides the domain switcher', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(domainSwitcher.trigger(page)).toBeVisible();

    await openFromUserMenu(page, 'Domains');

    await expect(page).toHaveURL(/\/org\/[^/]+\/domains$/);
    await expect(page.getByText(customDomain(), { exact: true }).first()).toBeVisible();
    await expect(domainSwitcher.trigger(page)).toHaveCount(0);
  });

  test('TC-SS-010: A domain detail page shows the domain switcher, enabled', async ({ page }) => {
    await page.goto('/dashboard');
    await domainSwitcher.trigger(page).click();
    const row = domainSwitcher
      .dropdown(page)
      .getByRole('menuitem')
      .filter({ hasText: customDomain() });
    await clickRowGear(page, row, 'Domain settings');

    await expect(page).toHaveURL(/\/org\/[^/]+\/domains\/[^/]+$/);
    await expect(domainSwitcher.trigger(page)).toBeEnabled();
    await expect(domainSwitcher.trigger(page)).toHaveAttribute('title', customDomain());
  });

  test('TC-SS-016: Account pages hide the domain switcher', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(domainSwitcher.trigger(page)).toBeVisible();

    await openFromUserMenu(page, 'Account');

    await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
    await expect(domainSwitcher.trigger(page)).toHaveCount(0);
  });

  test('TC-SS-030: Clicking the domain switcher opens a menu with the custom domain', async ({
    page,
  }) => {
    await page.goto('/dashboard');

    await domainSwitcher.trigger(page).click();

    await expect(domainSwitcher.dropdown(page)).toBeVisible();
    await expect(
      domainSwitcher.dropdown(page).getByRole('menuitem').filter({ hasText: customDomain() })
    ).toHaveCount(1);
  });

  test('TC-SS-031: Selecting a domain makes it the current scope and stores it for the tab', async ({
    page,
  }) => {
    await page.goto('/dashboard');
    await domainSwitcher.trigger(page).click();

    await domainSwitcher
      .dropdown(page)
      .getByRole('menuitem')
      .filter({ hasText: customDomain() })
      .click();

    await expect(domainSwitcher.dropdown(page)).toBeHidden();
    await expect(domainSwitcher.trigger(page)).toHaveAttribute('title', customDomain());
    await expect
      .poll(() => page.evaluate(() => sessionStorage.getItem('domainContext')))
      .toBe(customDomain());
  });

  test('TC-SS-033: The add-domain action opens the add-domain page', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await page.goto('/dashboard');
    await domainSwitcher.trigger(page).click();

    // With a custom domain, adding another is the header [+] icon
    await domainSwitcher.addIcon(page).click();

    await expect(page).toHaveURL(new RegExp(`/org/${org.extid}/domains/add$`));
  });

  test('TC-SS-042: A receipt page shows the domain switcher locked', async ({ page }) => {
    await page.goto('/dashboard');
    await page
      .getByRole('textbox', { name: 'Secret content' })
      .fill('scope switcher domain receipt');
    await page.getByTestId('split-button-submit').click();
    await page.waitForURL(/\/receipt\/[^/]+$/);

    const trigger = domainSwitcher.trigger(page);
    await expect(trigger).toBeDisabled();
    await expect(trigger).toHaveAttribute('aria-disabled', 'true');
    await expect(trigger).toHaveAttribute('title', 'Domain switching not available on this page');
  });

  test('TC-SS-052: The canonical domain row has no settings gear', async ({ page }) => {
    const response = await page.request.get('/bootstrap/me');
    expect(response.ok(), 'GET /bootstrap/me').toBe(true);
    const { canonical_domain, site_host } = (await response.json()) as {
      canonical_domain?: string;
      site_host?: string;
    };
    // The picker lists hosts without a port (normalizeDomainHost)
    const canonical = (canonical_domain || site_host || '').replace(/:\d+$/, '');
    expect(canonical, 'the bootstrap names the canonical domain').not.toBe('');

    await page.goto('/dashboard');

    await domainSwitcher.trigger(page).click();
    const row = domainSwitcher.dropdown(page).getByRole('menuitem').filter({ hasText: canonical });
    await expect(row).toHaveCount(1);
    await row.hover();
    await expect(row.getByRole('button', { name: 'Domain settings' })).toHaveCount(0);
  });

  test('TC-SS-061: The selected domain carries into in-app navigation', async ({ page }) => {
    await page.goto('/dashboard');
    await domainSwitcher.trigger(page).click();
    await domainSwitcher
      .dropdown(page)
      .getByRole('menuitem')
      .filter({ hasText: customDomain() })
      .click();
    await expect(domainSwitcher.trigger(page)).toHaveAttribute('title', customDomain());

    await openFromUserMenu(page, 'Account');
    await page.getByRole('link', { name: 'Back to Dashboard' }).click();

    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(domainSwitcher.trigger(page)).toHaveAttribute('title', customDomain());
  });

  test('TC-SS-071: The domain switcher trigger has an accessible name', async ({ page }) => {
    await page.goto('/dashboard');

    await expect(domainSwitcher.trigger(page)).toHaveAccessibleName('Switch domain scope');
  });
});

/**
 * Cases that need an account with two workspaces AND custom domains. The
 * throwaway owner has no custom domain and the storageState account is solo,
 * so neither lane account qualifies, with or without E2E_CUSTOM_DOMAINS.
 */
test.describe('Scope Switcher - two workspaces with custom domains', () => {
  test.fixme('TC-SS-009: A domain detail page shows the org switcher', async () => {
    // fixme: needs a multi-workspace account with a custom domain (#3420).
  });

  test.fixme('TC-SS-054: Switching workspace resets a domain scope the new workspace lacks', async () => {
    // fixme: needs two workspaces with different custom domains (#3420).
  });
});

/**
 * Qase Test Case Export Format
 *
 * Suite: Scope Switcher UX
 *
 * | ID         | Title                                                   | Priority | Automation |
 * |------------|---------------------------------------------------------|---------:|------------|
 * | TC-SS-001  | Dashboard: org switcher visible and enabled             | High     | Automated  |
 * | TC-SS-002  | Dashboard: domain switcher visible and enabled          | High     | Automated* |
 * | TC-SS-003  | /: signed-in owner lands on dashboard form with switcher| High     | Automated  |
 * | TC-SS-005  | Org settings: switching opens the other workspace       | High     | Automated  |
 * | TC-SS-006  | Org settings: domain switcher hidden                    | High     | Automated* |
 * | TC-SS-007  | /domains: Domains tab; switching keeps the tab          | Medium   | Automated  |
 * | TC-SS-008  | Domains tab: domain switcher hidden                     | Medium   | Automated* |
 * | TC-SS-009  | Domain detail: org switcher visible                     | Medium   | fixme      |
 * | TC-SS-010  | Domain detail: domain switcher enabled                  | High     | Automated* |
 * | TC-SS-015  | Account: org switcher hidden                            | High     | Automated  |
 * | TC-SS-016  | Account: domain switcher hidden                         | High     | Automated* |
 * | TC-SS-017  | Profile settings: org switcher hidden                   | Medium   | Automated  |
 * | TC-SS-018  | Security settings: org switcher hidden                  | Medium   | Automated  |
 * | TC-SS-020  | Org dropdown opens on click                             | High     | Automated  |
 * | TC-SS-021  | Dropdown lists workspaces, marks the current one        | High     | Automated  |
 * | TC-SS-022  | Selecting a workspace makes it current, saved in session| Critical | Automated  |
 * | TC-SS-023  | Row gear opens workspace settings                       | High     | Automated  |
 * | TC-SS-024  | Manage Workspaces opens /orgs                           | Medium   | Automated  |
 * | TC-SS-030  | Domain dropdown opens with the custom domain            | High     | Automated* |
 * | TC-SS-031  | Selecting a domain makes it current, stored for the tab | Critical | Automated* |
 * | TC-SS-033  | Add-domain action opens the add-domain page             | Medium   | Automated* |
 * | TC-SS-040  | Receipt: org switcher locked, shows current workspace   | High     | Automated  |
 * | TC-SS-041  | Receipt: locked switcher marked disabled for AT         | Medium   | Automated  |
 * | TC-SS-042  | Receipt: domain switcher locked                         | High     | Automated* |
 * | TC-SS-050  | Solo default workspace: no org switcher                 | High     | Automated  |
 * | TC-SS-051  | Domain switcher renders exactly when domains enabled    | High     | Automated  |
 * | TC-SS-052  | Canonical domain row has no settings gear               | Medium   | Automated* |
 * | TC-SS-053  | Keyboard: Enter, arrows, Escape                         | High     | Automated  |
 * | TC-SS-054  | Workspace switch resets unavailable domain scope        | High     | fixme      |
 * | TC-SS-060  | Selected workspace carries into in-app navigation       | High     | Automated  |
 * | TC-SS-061  | Selected domain carries into in-app navigation          | High     | Automated* |
 * | TC-SS-063  | Selected workspace survives a page reload               | Critical | Automated  |
 * | TC-SS-070  | Org switcher accessible name                            | Medium   | Automated  |
 * | TC-SS-071  | Domain switcher accessible name                         | Medium   | Automated* |
 * | TC-SS-072  | Dropdown is a menu labelled by its trigger              | Medium   | Automated  |
 * | TC-SS-073  | Rows and Manage link are menu items                     | Medium   | Automated  |
 * | TC-SS-074  | Tab closes the dropdown                                 | Medium   | Automated  |
 *
 * Automated* = runs only when E2E_CUSTOM_DOMAINS is set; test.fixme otherwise.
 *
 * Removed with the 2026-09 rewrite: TC-SS-004 (/ no longer renders a secret
 * form for a signed-in user; it redirects to the dashboard, covered by
 * TC-SS-002/003), TC-SS-011 to -014 (org switcher locked on /billing/*: the
 * billing routes moved to /billing/:extid/* and now show the switcher, and
 * they exist only with billing enabled), TC-SS-032 and TC-SS-062 (merged into
 * TC-SS-031).
 */
