// e2e/full/organization-members.spec.ts

/**
 * E2E Tests for Organization Member Management
 *
 * Tests the complete member management journey including:
 * - Viewing member list with roles and permissions
 * - Inviting new members (owner/admin)
 * - Changing member roles (owner only)
 * - Removing members (respecting role hierarchy)
 * - Accepting invitation flow
 *
 * Issue: https://github.com/onetimesecret/onetimesecret/issues/2888
 *
 * Role Hierarchy:
 * - Owner > Admin > Member
 * - Only owners can change roles
 * - Admins can remove members but not other admins
 * - Owner role cannot be assigned via UI
 *
 * Prerequisites:
 * - Authenticated as the org owner via the project storageState
 *   (e2e/global.setup.ts consumes TEST_USER_* and fails without them)
 * - Full auth mode with accounts that can sign in without verifying their
 *   email and no per-IP signup limit (the full lane sets
 *   AUTH_VERIFY_ACCOUNT_ENABLED=false and CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false)
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * The lane account is the only member of its default workspace. The role,
 * removal, hierarchy and permission suites need other members, so they build
 * a throwaway team (e2e/support/members.ts): a new owner, two admins and a
 * member who join through the real invitation flow. The shared owner's org
 * never gains a member.
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm test:playwright organization-members.spec.ts
 */

import {
  expect,
  type APIResponse,
  type Browser,
  type BrowserContext,
  type Locator,
  type Page,
  test,
} from '@playwright/test';

import {
  addMember,
  apiHeaders,
  closeContexts,
  createOwnerWithOrg,
  expectMember,
  invitationToken,
  inviteMember,
  openFreshContext,
  openMembersTab,
  signUpAccount,
  submitInviteSignup,
  uniqueTestEmail,
  generatePassword,
  type Account,
  type SignedInAccount,
} from '../support/members';
import { getFirstOrganization } from '../support/organizations';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Open the organization's Members tab through its legacy /team URL (the
 * internal tab is 'members') and wait for the members panel. Defaults to the
 * signed-in account's first organization.
 */
async function navigateToOrgTeam(page: Page, orgExtid?: string): Promise<string> {
  const extid = orgExtid ?? (await getFirstOrganization(page)).extid;

  await page.goto(`/org/${extid}/team`);
  await expect(page.getByTestId('org-section-members')).toBeVisible();
  return extid;
}

/**
 * The members table row for `email`. Emails are unique per test run, so the
 * substring match picks exactly one row.
 */
function memberRow(page: Page, email: string): Locator {
  return page.getByTestId('org-section-members').locator('tbody tr').filter({ hasText: email });
}

/** The role dropdown (Headless UI ListboxButton) in a members table row. */
function roleSelector(row: Locator): Locator {
  return row.locator('button[aria-haspopup="listbox"]');
}

/** The remove button in a members table row (aria-label "Remove Member"). */
function removeButton(row: Locator): Locator {
  return row.getByRole('button', { name: 'Remove Member' });
}

/** The page-level success alert in the Members panel. */
function membersAlert(page: Page, text: string): Locator {
  return page.getByTestId('org-section-members').getByText(text);
}

/**
 * Assert the server refused a member removal. RemoveMember raises a form
 * error with error_type 'forbidden', which the API answers with 422.
 */
async function expectRemovalRefused(response: APIResponse, errorKey: string): Promise<void> {
  expect(response.ok(), `removal answered HTTP ${response.status()}`).toBe(false);
  const body = await response.json();
  expect(body.error_type).toBe('forbidden');
  expect(body.error_key).toBe(errorKey);
}

/**
 * Customer extid of `email` in the org, read through the members API with
 * the page's session.
 */
async function memberExtid(page: Page, orgExtid: string, email: string): Promise<string> {
  const response = await page.request.get(`/api/organizations/${orgExtid}/members`);
  expect(response.ok(), `GET members for ${orgExtid}`).toBe(true);
  const records: { email: string; extid: string }[] = (await response.json()).records ?? [];
  const member = records.find((m) => m.email === email);
  expect(member?.extid, `${email} is listed in ${orgExtid}`).toBeTruthy();
  return member!.extid;
}

// -----------------------------------------------------------------------------
// Throwaway team for the role, removal, hierarchy and permission suites
// -----------------------------------------------------------------------------

type StorageState = Awaited<ReturnType<BrowserContext['storageState']>>;

interface TeamAccount extends Account {
  storageState: StorageState;
}

interface Team {
  orgExtid: string;
  owner: TeamAccount;
  admin: TeamAccount;
  otherAdmin: TeamAccount;
  member: TeamAccount;
}

/**
 * A new owner's default workspace with two admins and a member, each of whom
 * signed up through the invite page and accepted. Keeps every session as a
 * storageState so each test opens its own context.
 */
async function createTeam(browser: Browser): Promise<Team> {
  const opened: BrowserContext[] = [];
  const keep = async (account: SignedInAccount): Promise<TeamAccount> => ({
    email: account.email,
    password: account.password,
    storageState: await account.context.storageState(),
  });

  try {
    const { owner, orgExtid } = await createOwnerWithOrg(browser, opened, 'mbr-owner');
    const admin = await addMember(browser, opened, owner.page, orgExtid, 'admin', 'mbr-admin');
    const otherAdmin = await addMember(
      browser,
      opened,
      owner.page,
      orgExtid,
      'admin',
      'mbr-otheradmin'
    );
    const member = await addMember(browser, opened, owner.page, orgExtid, 'member', 'mbr-member');

    return {
      orgExtid,
      owner: await keep(owner),
      admin: await keep(admin),
      otherAdmin: await keep(otherAdmin),
      member: await keep(member),
    };
  } finally {
    await closeContexts(opened);
  }
}

// -----------------------------------------------------------------------------
// SECTION 1: Member List Display
// -----------------------------------------------------------------------------

test.describe('MBR-LIST: Organization Members List', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('MBR-LIST-001: Team tab appears in organization settings navigation', async ({ page }) => {
    const org = await getFirstOrganization(page);
    await page.goto(`/org/${org.extid}`);

    // The tab bar renders once the organization loads. The owner holds
    // manage_members, so the Members tab is present and enabled.
    const teamTab = page.getByTestId('org-tab-members');
    await expect(teamTab).toBeVisible();
    await expect(teamTab).toHaveAttribute('role', 'tab');
    await expect(teamTab).not.toHaveAttribute('aria-disabled', 'true');
  });

  test('MBR-LIST-002: Navigate to team tab shows members list', async ({ page }) => {
    const org = await getFirstOrganization(page);

    // The legacy /team URL opens the Members tab
    await page.goto(`/org/${org.extid}/team`);
    await expect(page.getByTestId('org-tab-members')).toHaveAttribute('aria-selected', 'true');

    const membersTable = page
      .getByTestId('org-section-members')
      .locator('table')
      .filter({ hasText: /member|role|joined/i });
    await expect(membersTable).toBeVisible();
  });

  test('MBR-LIST-003: Members list shows owner with correct role badge', async ({ page }) => {
    await navigateToOrgTeam(page);

    // Owner badge should be visible (amber colored)
    const ownerBadge = page.locator('span').filter({ hasText: /owner/i }).first();
    await expect(ownerBadge).toBeVisible({ timeout: 10000 });

    // Should have amber styling
    await expect(ownerBadge).toHaveClass(/amber/);
  });

  test('MBR-LIST-004: Members list displays member count', async ({ page }) => {
    await navigateToOrgTeam(page);

    // Member count should be displayed
    const memberCount = page.locator('p').filter({ hasText: /member|members/i });
    await expect(memberCount.first()).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 2: Invite Member Flow (Owner)
// -----------------------------------------------------------------------------

test.describe('MBR-INVITE: Invite Member Flow', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('MBR-INVITE-001: Owner can see and click Invite Member button', async ({ page }) => {
    await navigateToOrgTeam(page);

    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await expect(inviteButton).toBeVisible();
    await expect(inviteButton).toBeEnabled();
  });

  test('MBR-INVITE-002: Clicking Invite Member shows invitation form', async ({ page }) => {
    await navigateToOrgTeam(page);

    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await inviteButton.click();

    // Email input should appear
    const emailInput = page.locator('#invite-email');
    await expect(emailInput).toBeVisible({ timeout: 5000 });

    // Role selector should appear
    const roleSelect = page.locator('#invite-role');
    await expect(roleSelect).toBeVisible();

    // Should have member and admin options
    const memberOption = roleSelect.locator('option[value="member"]');
    const adminOption = roleSelect.locator('option[value="admin"]');
    await expect(memberOption).toBeAttached();
    await expect(adminOption).toBeAttached();

    // Owner option should NOT be available
    const ownerOption = roleSelect.locator('option[value="owner"]');
    await expect(ownerOption).not.toBeAttached();
  });

  test('MBR-INVITE-003: Submit valid invitation shows success and pending invitation', async ({
    page,
  }) => {
    await navigateToOrgTeam(page);

    const testEmail = uniqueTestEmail('invite');

    // Create invitation
    await inviteMember(page, testEmail, 'member');

    // Pending invitation should appear in list
    await expect(page.getByText(testEmail)).toBeVisible({ timeout: 10000 });

    // Pending badge should be visible. Scope to this invitation's row
    // (data-testid="org-invitation-row" in OrganizationSettings.vue) — a
    // bare .rounded-md matches the list container too, so the badge filter
    // would resolve to every pending invitation in the org (strict-mode
    // violation once prior runs leave rows behind).
    const pendingBadge = page
      .getByTestId('org-invitation-row')
      .filter({ hasText: testEmail })
      .locator('span')
      .filter({ hasText: /pending/i })
      .first();
    await expect(pendingBadge).toBeVisible();
  });

  test('MBR-INVITE-004: Invitation form validates email format', async ({ page }) => {
    await navigateToOrgTeam(page);

    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await inviteButton.click();

    const emailInput = page.locator('#invite-email');
    await emailInput.fill('invalid-email');

    const sendButton = page.getByRole('button', { name: /send invit/i });
    await sendButton.click();

    // Should show validation error or HTML5 validation prevents submission
    // HTML5 email validation should trigger
    const isInvalid = await emailInput.evaluate((el: HTMLInputElement) => !el.validity.valid);
    expect(isInvalid).toBe(true);
  });

  test('MBR-INVITE-005: Inviting existing member shows error', async ({ page }) => {
    await navigateToOrgTeam(page);

    // Get the owner's email (who is already a member)
    const bootstrapResponse = await page.request.get('/bootstrap/me');
    const bootstrapData = await bootstrapResponse.json();
    const ownerEmail = bootstrapData.email;
    expect(ownerEmail, '/bootstrap/me carries the signed-in email').toBeTruthy();

    // Try to invite the owner
    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await inviteButton.click();

    const emailInput = page.locator('#invite-email');
    await emailInput.fill(ownerEmail);

    const sendButton = page.getByRole('button', { name: /send invit/i });
    await sendButton.click();

    // Should show error about already being a member. Keep the pattern
    // specific: bare /member/i matches the team page chrome (Invite Member
    // button, Members heading) and trips strict mode.
    await expect(page.getByText(/already a member/i)).toBeVisible({ timeout: 10000 });
  });
});

// -----------------------------------------------------------------------------
// SECTION 3: Invitation Management (Resend/Revoke)
// -----------------------------------------------------------------------------

test.describe('MBR-INVMGMT: Invitation Management', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('MBR-INVMGMT-001: Owner can resend pending invitation', async ({ page }) => {
    await navigateToOrgTeam(page);

    const testEmail = uniqueTestEmail('resend');
    await inviteMember(page, testEmail);

    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    await invitationRow.getByRole('button', { name: 'Resend' }).click();

    await expect(page.getByText('Invitation resent successfully')).toBeVisible();
    // Still pending after the resend
    await expect(invitationRow.getByText('Pending', { exact: true })).toBeVisible();
  });

  test('MBR-INVMGMT-002: Owner can revoke pending invitation', async ({ page }) => {
    await navigateToOrgTeam(page);

    const testEmail = uniqueTestEmail('revoke');
    await inviteMember(page, testEmail);

    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    await invitationRow.getByRole('button', { name: 'Revoke' }).click();

    await expect(page.getByText('Invitation revoked successfully')).toBeVisible();
    await expect(invitationRow).toHaveCount(0);
  });
});

// -----------------------------------------------------------------------------
// SECTION 4: Accept Invitation Flow
// -----------------------------------------------------------------------------

test.describe('MBR-ACCEPT: Accept Invitation Flow', () => {
  test('MBR-ACCEPT-001: Valid invitation token shows invitation details', async ({
    page,
    browser,
  }) => {
    // Create invitation as owner (storageState session)
    const org = await getFirstOrganization(page);
    await navigateToOrgTeam(page, org.extid);

    const testEmail = uniqueTestEmail('accept');
    await inviteMember(page, testEmail);
    const token = await invitationToken(page, org.extid, testEmail);

    // An unauthenticated visitor lands in the signup_required state: the
    // invitation context names the organization and the email field is bound
    // to the invited address.
    const opened: BrowserContext[] = [];
    try {
      const visitorPage = await (await openFreshContext(browser, opened)).newPage();
      await visitorPage.goto(`/invite/${token}`);

      await expect(visitorPage.getByTestId('invite-signup-required')).toBeVisible();
      await expect(visitorPage.getByTestId('invitation-context')).toContainText(org.name);
      await expect(visitorPage.getByTestId('invite-signup-email-input')).toHaveValue(testEmail);
    } finally {
      await closeContexts(opened);
    }
  });

  test('MBR-ACCEPT-002: Unauthenticated user sees sign-in form (signin_required state)', async ({
    page,
    browser,
  }) => {
    const opened: BrowserContext[] = [];
    try {
      // The invited email already has an account; its owner is signed out
      const inviteePage = await (await openFreshContext(browser, opened)).newPage();
      const invitedEmail = uniqueTestEmail('accept-existing');
      await signUpAccount(inviteePage, invitedEmail, generatePassword());

      // Invite it as the shared owner. Nothing is accepted, so the owner's
      // org gains only a pending invitation.
      const orgExtid = await navigateToOrgTeam(page);
      await inviteMember(page, invitedEmail);
      const token = await invitationToken(page, orgExtid, invitedEmail);

      // The page cannot know the account exists (AZ7/#3856), so it offers
      // signup first. The backend answers signup_unavailable and the view
      // switches to signin_required.
      await inviteePage.goto(`/invite/${token}`);
      await expect(inviteePage.getByTestId('invite-signup-required')).toBeVisible();
      await submitInviteSignup(inviteePage, generatePassword());

      await expect(inviteePage.getByTestId('invite-signin-required')).toBeVisible();
      await expect(inviteePage.getByTestId('sign-in-notice')).toBeVisible();
      await expect(inviteePage.getByTestId('invite-signin-form')).toBeVisible();
      await expect(inviteePage.getByTestId('invite-signin-email-input')).toHaveValue(invitedEmail);

      // Signing in comes first: the direct accept/decline controls are absent
      await expect(inviteePage.getByTestId('accept-invitation-btn')).toHaveCount(0);
      await expect(inviteePage.getByTestId('decline-invitation-btn')).toHaveCount(0);
    } finally {
      await closeContexts(opened);
    }
  });

  test('MBR-ACCEPT-003: Unauthenticated invitee can decline from the invite page', async ({
    page,
    browser,
  }) => {
    // Create invitation as owner (storageState session)
    const orgExtid = await navigateToOrgTeam(page);

    const testEmail = uniqueTestEmail('decline');
    await inviteMember(page, testEmail);
    const token = await invitationToken(page, orgExtid, testEmail);

    // Without a session the invite page shows the inline signup form, which
    // carries its own Decline control (POST /api/invite/:token/decline is
    // auth=noauth).
    const opened: BrowserContext[] = [];
    try {
      const inviteePage = await (await openFreshContext(browser, opened)).newPage();
      await inviteePage.goto(`/invite/${token}`);

      await expect(inviteePage.getByTestId('invite-signup-required')).toBeVisible();
      await inviteePage.getByTestId('invite-signup-decline').click();
      await expect(inviteePage.getByTestId('invite-declined')).toBeVisible();
    } finally {
      await closeContexts(opened);
    }

    // The declined invitation left the org's pending list
    const response = await page.request.get(`/api/organizations/${orgExtid}/invitations`);
    expect(response.ok()).toBe(true);
    const pendingEmails = ((await response.json()).records ?? []).map(
      (inv: { email: string }) => inv.email
    );
    expect(pendingEmails).not.toContain(testEmail);
  });
});

// -----------------------------------------------------------------------------
// SECTIONS 5-8: Roles, removal, hierarchy and permissions (throwaway team)
// -----------------------------------------------------------------------------

test.describe('MBR-TEAM: Member management with non-owner members', () => {
  let team: Team;
  const opened: BrowserContext[] = [];

  test.beforeAll(async ({ browser }) => {
    // Four signups and three invitation round trips
    test.setTimeout(180_000);
    team = await createTeam(browser);
  });

  test.afterEach(async () => {
    await closeContexts(opened);
  });

  /** A page signed in as a team account, in its own context. */
  async function openAs(browser: Browser, account: TeamAccount): Promise<Page> {
    const context = await browser.newContext({ storageState: account.storageState });
    opened.push(context);
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    return page;
  }

  // ---------------------------------------------------------------------------
  // SECTION 5: Change Member Role (Owner Only)
  // ---------------------------------------------------------------------------

  test.describe('MBR-ROLE: Change Member Role', () => {
    test('MBR-ROLE-001: Owner sees role selector dropdown for non-owner members', async ({
      browser,
    }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      await expect(roleSelector(memberRow(page, team.member.email))).toHaveText('Member');
      await expect(roleSelector(memberRow(page, team.admin.email))).toHaveText('Admin');
      await expect(roleSelector(memberRow(page, team.owner.email))).toHaveCount(0);
    });

    test('MBR-ROLE-002: Owner can change member role from member to admin', async ({ browser }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      // A member of its own, so the shared team keeps its roles
      const promoted = await addMember(
        browser,
        opened,
        page,
        team.orgExtid,
        'member',
        'mbr-promote'
      );
      await openMembersTab(page, team.orgExtid);

      const selector = roleSelector(memberRow(page, promoted.email));
      await expect(selector).toHaveText('Member');
      await selector.click();
      await page.getByRole('option', { name: /^Admin/ }).click();

      await expect(membersAlert(page, 'Member role updated successfully')).toBeVisible();
      await expect(selector).toHaveText('Admin');
      await expectMember(page, team.orgExtid, promoted.email, 'admin');
    });

    test('MBR-ROLE-003: Owner cannot change owner role', async ({ browser }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      // The other rows carry role dropdowns; the owner's role is a static badge
      await expect(roleSelector(memberRow(page, team.member.email))).toBeVisible();
      const roleCell = memberRow(page, team.owner.email).locator('td').nth(1);
      await expect(roleCell).toHaveText('Owner');
      await expect(roleCell.getByRole('button')).toHaveCount(0);
    });

    test('MBR-ROLE-004: Role selector shows only admin and member options (not owner)', async ({
      browser,
    }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      await roleSelector(memberRow(page, team.member.email)).click();

      const listbox = page.getByRole('listbox');
      await expect(listbox).toBeVisible();
      const options = listbox.getByRole('option');
      await expect(options).toHaveCount(2);
      await expect(options.nth(0)).toContainText('Admin');
      await expect(options.nth(1)).toContainText('Member');
      await expect(listbox.getByRole('option', { name: /owner/i })).toHaveCount(0);

      // Close without choosing: the member keeps its role. Headless UI focuses
      // the options list on the tick after it opens, and only the options list
      // handles Escape, so wait for that focus before pressing it.
      await expect(listbox).toBeFocused();
      await page.keyboard.press('Escape');
      await expect(listbox).toBeHidden();
      await expectMember(page, team.orgExtid, team.member.email, 'member');
    });
  });

  // ---------------------------------------------------------------------------
  // SECTION 6: Remove Member
  // ---------------------------------------------------------------------------

  test.describe('MBR-REMOVE: Remove Member', () => {
    test('MBR-REMOVE-001: Owner sees remove button for non-owner members', async ({ browser }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      // The owner can remove admins and members
      await expect(removeButton(memberRow(page, team.member.email))).toBeVisible();
      await expect(removeButton(memberRow(page, team.admin.email))).toBeVisible();
    });

    test('MBR-REMOVE-002: Remove button not shown for owner row', async ({ browser }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      // The owner row's actions cell shows "--" instead of a remove button
      await expect(removeButton(memberRow(page, team.member.email))).toBeVisible();
      const row = memberRow(page, team.owner.email);
      await expect(row.locator('td').last()).toHaveText('--');
      await expect(removeButton(row)).toHaveCount(0);
    });

    test('MBR-REMOVE-003: Clicking remove shows confirmation dialog', async ({ browser }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      await removeButton(memberRow(page, team.member.email)).click();

      const dialog = page.getByTestId('confirm-dialog');
      await expect(dialog).toBeVisible();
      await expect(dialog).toContainText(team.member.email);
      await expect(page.getByTestId('confirm-dialog-confirm')).toBeVisible();

      // Cancel leaves the member in place
      await page.getByTestId('confirm-dialog-cancel').click();
      await expect(dialog).toBeHidden();
      await expect(memberRow(page, team.member.email)).toBeVisible();
      await expectMember(page, team.orgExtid, team.member.email, 'member');
    });

    test('MBR-REMOVE-004: Confirming removal removes member from list', async ({ browser }) => {
      const page = await openAs(browser, team.owner);
      await openMembersTab(page, team.orgExtid);

      // A member of its own, so the shared team stays intact
      const leaving = await addMember(browser, opened, page, team.orgExtid, 'member', 'mbr-remove');
      await openMembersTab(page, team.orgExtid);

      await removeButton(memberRow(page, leaving.email)).click();
      await page.getByTestId('confirm-dialog-confirm').click();

      await expect(membersAlert(page, 'Member removed from organization')).toBeVisible();
      await expect(memberRow(page, leaving.email)).toHaveCount(0);

      const response = await page.request.get(`/api/organizations/${team.orgExtid}/members`);
      expect(response.ok()).toBe(true);
      const emails = ((await response.json()).records ?? []).map((m: { email: string }) => m.email);
      expect(emails).not.toContain(leaving.email);
    });
  });

  // ---------------------------------------------------------------------------
  // SECTION 7: Role Hierarchy Enforcement
  // ---------------------------------------------------------------------------

  test.describe('MBR-HIERARCHY: Role Hierarchy Enforcement', () => {
    test('MBR-HIERARCHY-001: Admin cannot change member roles (dropdown not shown)', async ({
      browser,
    }) => {
      const page = await openAs(browser, team.admin);
      await openMembersTab(page, team.orgExtid);

      // Every role renders as a static badge for an admin
      await expect(memberRow(page, team.member.email).locator('td').nth(1)).toHaveText('Member');
      await expect(memberRow(page, team.otherAdmin.email).locator('td').nth(1)).toHaveText('Admin');
      await expect(memberRow(page, team.owner.email).locator('td').nth(1)).toHaveText('Owner');
      await expect(
        page.getByTestId('org-section-members').locator('button[aria-haspopup="listbox"]')
      ).toHaveCount(0);
    });

    test('MBR-HIERARCHY-002: Admin can remove members but not other admins', async ({
      browser,
    }) => {
      const page = await openAs(browser, team.admin);
      await openMembersTab(page, team.orgExtid);

      await expect(removeButton(memberRow(page, team.member.email))).toBeVisible();
      await expect(removeButton(memberRow(page, team.otherAdmin.email))).toHaveCount(0);
      await expect(removeButton(memberRow(page, team.owner.email))).toHaveCount(0);
      // Nobody removes themselves from the table (leaving is separate)
      await expect(removeButton(memberRow(page, team.admin.email))).toHaveCount(0);

      // The server enforces the same rule
      const otherAdminExtid = await memberExtid(page, team.orgExtid, team.otherAdmin.email);
      const response = await page.request.delete(
        `/api/organizations/${team.orgExtid}/members/${otherAdminExtid}`,
        { headers: await apiHeaders(page) }
      );
      await expectRemovalRefused(
        response,
        'api.organizations.members.errors.admin_cannot_remove_admin'
      );
      await expectMember(page, team.orgExtid, team.otherAdmin.email, 'admin');
    });
  });

  // ---------------------------------------------------------------------------
  // SECTION 8: Permission Denied States
  // ---------------------------------------------------------------------------

  test.describe('MBR-PERM: Permission Denied States', () => {
    test('MBR-PERM-001: Member role user cannot invite new members', async ({ browser }) => {
      const page = await openAs(browser, team.member);

      // Org settings require the admin role: the members page redirects away
      await page.goto(`/org/${team.orgExtid}/members`);
      await expect(page).toHaveURL(/\/dashboard$/);
      await expect(page.getByTestId('org-section-members')).toHaveCount(0);
      await expect(page.getByRole('button', { name: /invite member/i })).toHaveCount(0);

      // ...and the invitations API refuses a member
      const response = await page.request.post(`/api/organizations/${team.orgExtid}/invitations`, {
        headers: await apiHeaders(page),
        data: { email: uniqueTestEmail('perm-invite'), role: 'member' },
      });
      expect(response.status()).toBe(403);
    });

    test('MBR-PERM-002: Member role user cannot remove members', async ({ browser }) => {
      const page = await openAs(browser, team.member);

      // No members page, so no remove buttons
      await page.goto(`/org/${team.orgExtid}/members`);
      await expect(page).toHaveURL(/\/dashboard$/);
      await expect(page.getByRole('button', { name: 'Remove Member' })).toHaveCount(0);

      // ...and the members API refuses a member's removal request
      const ownerPage = await openAs(browser, team.owner);
      const adminExtid = await memberExtid(ownerPage, team.orgExtid, team.otherAdmin.email);
      const response = await page.request.delete(
        `/api/organizations/${team.orgExtid}/members/${adminExtid}`,
        { headers: await apiHeaders(page) }
      );
      await expectRemovalRefused(
        response,
        'api.organizations.members.errors.no_permission_to_remove'
      );
      await expectMember(ownerPage, team.orgExtid, team.otherAdmin.email, 'admin');
    });
  });
});

/**
 * Test Case Reference (Qase-compatible)
 *
 * Suite: Organization Member Management
 *
 * | ID              | Title                                              | Priority   | Automation |
 * |-----------------|----------------------------------------------------|------------|------------|
 * | MBR-LIST-001    | Team tab appears in org settings navigation        | Critical   | Automated  |
 * | MBR-LIST-002    | Navigate to team tab shows members list            | Critical   | Automated  |
 * | MBR-LIST-003    | Members list shows owner with correct role badge   | High       | Automated  |
 * | MBR-LIST-004    | Members list displays member count                 | Medium     | Automated  |
 * | MBR-INVITE-001  | Owner can see and click Invite Member button       | Critical   | Automated  |
 * | MBR-INVITE-002  | Clicking Invite Member shows invitation form       | Critical   | Automated  |
 * | MBR-INVITE-003  | Submit valid invitation shows success              | Critical   | Automated  |
 * | MBR-INVITE-004  | Invitation form validates email format             | High       | Automated  |
 * | MBR-INVITE-005  | Inviting existing member shows error               | High       | Automated  |
 * | MBR-ROLE-001    | Owner sees role selector for non-owner members     | Critical   | Automated  |
 * | MBR-ROLE-002    | Owner can change member role to admin              | Critical   | Automated  |
 * | MBR-ROLE-003    | Owner cannot change owner role                     | Critical   | Automated  |
 * | MBR-ROLE-004    | Role selector shows only admin and member          | High       | Automated  |
 * | MBR-REMOVE-001  | Owner sees remove button for non-owner members     | Critical   | Automated  |
 * | MBR-REMOVE-002  | Remove button not shown for owner row              | Critical   | Automated  |
 * | MBR-REMOVE-003  | Clicking remove shows confirmation dialog          | High       | Automated  |
 * | MBR-REMOVE-004  | Confirming removal removes member from list        | Critical   | Automated  |
 * | MBR-INVMGMT-001 | Owner can resend pending invitation                | Medium     | Automated  |
 * | MBR-INVMGMT-002 | Owner can revoke pending invitation                | Medium     | Automated  |
 * | MBR-ACCEPT-001  | Valid invitation token shows details               | Critical   | Automated  |
 * | MBR-ACCEPT-002  | Existing-account invitee is asked to sign in       | Critical   | Automated  |
 * | MBR-ACCEPT-003  | Unauthenticated invitee can decline                | High       | Automated  |
 * | MBR-HIERARCHY-001| Admin cannot change member roles                  | Critical   | Automated  |
 * | MBR-HIERARCHY-002| Admin can remove members but not other admins     | Critical   | Automated  |
 * | MBR-PERM-001    | Member role user cannot invite new members         | High       | Automated  |
 * | MBR-PERM-002    | Member role user cannot remove members             | High       | Automated  |
 */
