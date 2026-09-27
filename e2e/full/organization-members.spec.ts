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
 * - Authenticated as the org owner via the project storageState (e2e/global.setup.ts consumes TEST_USER_*)
 * - Set TEST_ADMIN_EMAIL and TEST_ADMIN_PASSWORD for admin user tests (optional)
 * - Set TEST_MEMBER_EMAIL and TEST_MEMBER_PASSWORD for member user tests (optional)
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm test:playwright organization-members.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

import { getFirstOrganization } from '../support/organizations';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// Generate unique email addresses for test isolation
const generateTestEmail = (prefix: string) =>
  `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.onetimesecret.com`;

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Sign in as a *different* account than the shared session (e.g. the
 * TEST_ADMIN_* / TEST_MEMBER_* role accounts in the hierarchy/permission
 * suites below).
 *
 * The `full` project starts every test already authenticated as TEST_USER_*
 * via storageState (e2e/playwright.config.ts), so the session must be
 * dropped first — an authenticated visitor to /signin is redirected away
 * and never sees the form.
 */
async function loginUser(page: Page, email?: string, password?: string): Promise<void> {
  await page.context().clearCookies();
  await page.goto('/signin');

  // Click Password tab - Magic Link is the default, password input is hidden
  // Handle both signin variants (canonical logic: e2e/global.setup.ts):
  // default deployments render SignInForm directly (the CI container does);
  // passwordless-first deployments hide the password panel behind a
  // "Password" tab with different test ids.
  const signinEmail = email || process.env.TEST_USER_EMAIL || '';
  const signinPassword = password || process.env.TEST_USER_PASSWORD || '';
  const signinForm = page.getByTestId('signin-form');
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await expect(signinForm.or(passwordTab).first()).toBeVisible();

  if (await passwordTab.isVisible()) {
    // Passwordless-first variant (magic links / WebAuthn enabled)
    await passwordTab.click();
    await page.getByTestId('password-email-input').fill(signinEmail);
    await page.getByTestId('password-input').fill(signinPassword);
    await page.getByTestId('password-submit').click();
  } else {
    // Password-only variant (CI container default)
    await page.getByTestId('signin-email-input').fill(signinEmail);
    await page.getByTestId('signin-password-input').fill(signinPassword);
    await page.getByTestId('signin-submit').click();
  }

  // Wait for redirect to dashboard/account
  await page.waitForURL(/\/(account|dashboard|org)/, { timeout: 30000 });
}

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
 * Get current organization extid from URL
 */
function getCurrentOrgExtid(page: Page): string {
  const url = page.url();
  const match = url.match(/\/org\/([^/]+)/);
  return match?.[1] || '';
}

/**
 * The signed-in owner's row in the members table (the lane account is the
 * org owner). Waits for the row to render.
 */
function ownerRow(page: Page) {
  return page
    .getByTestId('org-section-members')
    .locator('tbody tr')
    .filter({ hasText: process.env.TEST_USER_EMAIL ?? '' });
}

/**
 * Create a new invitation via the UI
 */
async function createInvitation(
  page: Page,
  email: string,
  role: 'member' | 'admin' = 'member'
): Promise<void> {
  // Click invite member button
  const inviteButton = page.getByRole('button', { name: /invite member/i });
  await inviteButton.click();

  // Fill invitation form
  const emailInput = page.locator('#invite-email');
  await emailInput.fill(email);

  const roleSelect = page.locator('#invite-role');
  await roleSelect.selectOption(role);

  // Submit
  const sendButton = page.getByRole('button', { name: /send invitation/i });
  await sendButton.click();

  // Wait for success
  await expect(page.getByText(/invitation sent/i)).toBeVisible({ timeout: 10000 });
}

/**
 * Extract invitation token from pending invitations list via API
 */
async function getInvitationToken(page: Page, email: string): Promise<string | null> {
  const orgExtid = getCurrentOrgExtid(page);
  const response = await page.request.get(`/api/organizations/${orgExtid}/invitations`);
  const data = await response.json();

  const invitation = data.records?.find((inv: { email: string }) => inv.email === email);
  return invitation?.token || null;
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

    const testEmail = generateTestEmail('invite');

    // Create invitation
    await createInvitation(page, testEmail, 'member');

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
// SECTION 3: Change Member Role (Owner Only)
// -----------------------------------------------------------------------------

test.describe('MBR-ROLE: Change Member Role', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  // fixme: needs a non-owner member in the org. The lane account is the only
  // member of its default workspace, so no row has a role selector or a remove
  // button. See #3419.
  test.fixme('MBR-ROLE-001: Owner sees role selector dropdown for non-owner members', async ({
    page,
  }) => {
    await navigateToOrgTeam(page);

    // A role dropdown (Listbox button) in a member row. Scoped to the table
    // body: page-wide, /member/ also matches the Invite Member button.
    const roleDropdown = page
      .getByTestId('org-section-members')
      .locator('tbody button')
      .filter({ hasText: /member|admin/i })
      .first();
    await expect(roleDropdown).toBeVisible();
  });

  // fixme: needs a non-owner member in the org. The lane account is the only
  // member of its default workspace, so no row has a role selector or a remove
  // button. See #3419.
  test.fixme('MBR-ROLE-002: Owner can change member role from member to admin', async ({
    page,
  }) => {
    await navigateToOrgTeam(page);

    // Find a role dropdown that shows "member"
    const memberRoleButton = page
      .getByTestId('org-section-members')
      .locator('tbody button')
      .filter({ hasText: /^member$/i })
      .first();
    await expect(memberRoleButton).toBeVisible();

    // Click to open dropdown
    await memberRoleButton.click();

    // Select admin option
    const adminOption = page.locator('[role="listbox"] li').filter({ hasText: /admin/i });
    await adminOption.click();

    // Verify success message
    await expect(page.getByText(/role updated|updated/i)).toBeVisible({ timeout: 10000 });

    // Verify role changed (admin badge now visible in that row)
    await expect(page.locator('span').filter({ hasText: /admin/i })).toBeVisible();
  });

  test('MBR-ROLE-003: Owner cannot change owner role', async ({ page }) => {
    await navigateToOrgTeam(page);

    // The owner's role renders as a static badge, not a role dropdown
    const roleCell = ownerRow(page).locator('td').nth(1);
    await expect(roleCell).toHaveText('Owner');
    await expect(roleCell.getByRole('button')).toHaveCount(0);
  });

  // fixme: needs a non-owner member in the org. The lane account is the only
  // member of its default workspace, so no row has a role selector or a remove
  // button. See #3419.
  test.fixme('MBR-ROLE-004: Role selector shows only admin and member options (not owner)', async ({
    page,
  }) => {
    await navigateToOrgTeam(page);

    // Find any role dropdown in a member row
    const roleDropdown = page
      .getByTestId('org-section-members')
      .locator('tbody button')
      .filter({ hasText: /member|admin/i })
      .filter({ hasNotText: /owner/i })
      .first();
    await expect(roleDropdown).toBeVisible();

    await roleDropdown.click();

    // Check available options
    const listbox = page.locator('[role="listbox"]');
    await expect(listbox).toBeVisible();

    const options = listbox.locator('li');
    const optionTexts = await options.allTextContents();

    // Should have admin and member
    const hasAdmin = optionTexts.some((t) => /admin/i.test(t));
    const hasMember = optionTexts.some((t) => /member/i.test(t));
    const hasOwner = optionTexts.some((t) => /owner/i.test(t));

    expect(hasAdmin).toBe(true);
    expect(hasMember).toBe(true);
    expect(hasOwner).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// SECTION 4: Remove Member
// -----------------------------------------------------------------------------

test.describe('MBR-REMOVE: Remove Member', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  // fixme: needs a non-owner member in the org. The lane account is the only
  // member of its default workspace, so no row has a role selector or a remove
  // button. See #3419.
  test.fixme('MBR-REMOVE-001: Owner sees remove button for non-owner members', async ({ page }) => {
    await navigateToOrgTeam(page);

    await expect(page.getByRole('button', { name: /remove member/i }).first()).toBeVisible();
  });

  test('MBR-REMOVE-002: Remove button not shown for owner row', async ({ page }) => {
    await navigateToOrgTeam(page);

    // The owner row's actions cell shows "--" instead of a remove button
    const row = ownerRow(page);
    await expect(row.locator('td').last()).toHaveText('--');
    await expect(row.getByRole('button', { name: /remove member/i })).toHaveCount(0);
  });

  // fixme: needs a non-owner member in the org. The lane account is the only
  // member of its default workspace, so no row has a role selector or a remove
  // button. See #3419.
  test.fixme('MBR-REMOVE-003: Clicking remove shows confirmation dialog', async ({ page }) => {
    await navigateToOrgTeam(page);

    // Find first remove button
    const removeButton = page.getByRole('button', { name: /remove member/i }).first();
    await expect(removeButton).toBeVisible();

    await removeButton.click();

    // Confirmation dialog should appear
    const confirmDialog = page.locator('[role="dialog"], [role="alertdialog"]');
    await expect(confirmDialog).toBeVisible({ timeout: 5000 });

    // Should have confirm/cancel actions
    const confirmButton = page.getByRole('button', { name: /confirm|remove|yes/i });
    const cancelButton = page.getByRole('button', { name: /cancel|no/i });

    await expect(confirmButton).toBeVisible();
    await expect(cancelButton).toBeVisible();
  });

  // fixme: needs a non-owner member in the org. The lane account is the only
  // member of its default workspace, so no row has a role selector or a remove
  // button. See #3419.
  test.fixme('MBR-REMOVE-004: Confirming removal removes member from list', async ({ page }) => {
    await navigateToOrgTeam(page);

    const removeButton = page.getByRole('button', { name: /remove member/i }).first();
    await expect(removeButton).toBeVisible();

    // Get the email of member being removed (for verification)
    const memberRow = removeButton.locator('xpath=ancestor::tr');
    const memberEmail = await memberRow.locator('td').first().textContent();

    // Click remove
    await removeButton.click();

    // Confirm in dialog
    const confirmButton = page.getByRole('button', { name: /confirm|remove|yes/i });
    await confirmButton.click();

    // Success message should appear
    await expect(page.getByText(/removed|success/i)).toBeVisible({ timeout: 10000 });

    // Member should no longer be in the list
    if (memberEmail) {
      await expect(page.getByText(memberEmail.trim())).not.toBeVisible({ timeout: 5000 });
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 5: Invitation Management (Resend/Revoke)
// -----------------------------------------------------------------------------

test.describe('MBR-INVMGMT: Invitation Management', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('MBR-INVMGMT-001: Owner can resend pending invitation', async ({ page }) => {
    await navigateToOrgTeam(page);

    const testEmail = generateTestEmail('resend');
    await createInvitation(page, testEmail);

    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    await invitationRow.getByRole('button', { name: 'Resend' }).click();

    await expect(page.getByText('Invitation resent successfully')).toBeVisible();
    // Still pending after the resend
    await expect(invitationRow.getByText('Pending', { exact: true })).toBeVisible();
  });

  test('MBR-INVMGMT-002: Owner can revoke pending invitation', async ({ page }) => {
    await navigateToOrgTeam(page);

    const testEmail = generateTestEmail('revoke');
    await createInvitation(page, testEmail);

    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    await invitationRow.getByRole('button', { name: 'Revoke' }).click();

    await expect(page.getByText('Invitation revoked successfully')).toBeVisible();
    await expect(invitationRow).toHaveCount(0);
  });
});

// -----------------------------------------------------------------------------
// SECTION 6: Accept Invitation Flow
// -----------------------------------------------------------------------------

test.describe('MBR-ACCEPT: Accept Invitation Flow', () => {
  test('MBR-ACCEPT-001: Valid invitation token shows invitation details', async ({
    page,
    browser,
  }) => {
    // Create invitation as owner (storageState session)
    const org = await getFirstOrganization(page);
    await navigateToOrgTeam(page, org.extid);

    const testEmail = generateTestEmail('accept');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // An unauthenticated visitor lands in the signup_required state: the
    // invitation context names the organization and the email field is bound
    // to the invited address. browser.newContext() would inherit the owner
    // session.
    const visitorContext = await browser.newContext({
      storageState: { cookies: [], origins: [] },
    });
    try {
      const visitorPage = await visitorContext.newPage();
      await visitorPage.goto(`/invite/${token}`);

      await expect(visitorPage.getByTestId('invite-signup-required')).toBeVisible();
      await expect(visitorPage.getByTestId('invitation-context')).toContainText(org.name);
      await expect(visitorPage.getByTestId('invite-signup-email-input')).toHaveValue(testEmail);
    } finally {
      await visitorContext.close();
    }
  });

  // fixme: signin_required only follows a signup attempt for an invited email
  // that already has an account (AZ7/#3856). This test invites a fresh address
  // and expects the state on arrival. The lane can create that account (see
  // INV-004 in invite-flow-states.spec.ts, which covers this state); rewrite it
  // once those throwaway-account helpers move to e2e/support. See #3419.
  test.fixme('MBR-ACCEPT-002: Unauthenticated user sees sign-in form (signin_required state)', async ({
    page,
    context,
  }) => {
    // Create invitation as owner (storageState session)
    await navigateToOrgTeam(page);

    const testEmail = generateTestEmail('accept-unauth');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies to become unauthenticated
    await context.clearCookies();

    // Visit invitation as unauthenticated user
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // In signin_required state, the component shows inline sign-in form
    // Sign-in notice should be visible (not accept/decline buttons)
    const signInNotice = page.getByTestId('sign-in-notice');
    await expect(signInNotice).toBeVisible();

    // Accept/decline buttons should NOT be visible in this state
    const acceptButton = page.getByTestId('accept-invitation-btn');
    await expect(acceptButton).not.toBeVisible();

    const declineButton = page.getByTestId('decline-invitation-btn');
    await expect(declineButton).not.toBeVisible();
  });

  test('MBR-ACCEPT-003: Unauthenticated invitee can decline from the invite page', async ({
    page,
    browser,
  }) => {
    // Create invitation as owner (storageState session)
    const orgExtid = await navigateToOrgTeam(page);

    const testEmail = generateTestEmail('decline');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Without a session the invite page shows the inline signup form, which
    // carries its own Decline control (POST /api/invite/:token/decline is
    // auth=noauth). browser.newContext() would inherit the owner session.
    const inviteeContext = await browser.newContext({
      storageState: { cookies: [], origins: [] },
    });
    try {
      const inviteePage = await inviteeContext.newPage();
      await inviteePage.goto(`/invite/${token}`);

      await expect(inviteePage.getByTestId('invite-signup-required')).toBeVisible();
      await inviteePage.getByTestId('invite-signup-decline').click();
      await expect(inviteePage.getByTestId('invite-declined')).toBeVisible();
    } finally {
      await inviteeContext.close();
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
// SECTION 7: Role Hierarchy Enforcement
// -----------------------------------------------------------------------------

test.describe('MBR-HIERARCHY: Role Hierarchy Enforcement', () => {
  // These tests require admin credentials
  const hasAdminCredentials = !!(
    process.env.TEST_ADMIN_EMAIL && process.env.TEST_ADMIN_PASSWORD
  );

  test.skip(
    !hasTestCredentials || !hasAdminCredentials,
    'Skipping: Requires TEST_USER and TEST_ADMIN credentials'
  );

  test('MBR-HIERARCHY-001: Admin cannot change member roles (dropdown not shown)', async ({
    page,
  }) => {
    // Login as admin
    await loginUser(
      page,
      process.env.TEST_ADMIN_EMAIL,
      process.env.TEST_ADMIN_PASSWORD
    );

    await navigateToOrgTeam(page);

    // Admin should see static role badges, not dropdowns for other members
    // Check that no role dropdowns are clickable
    const roleDropdowns = page.locator('button').filter({ hasText: /member|admin/i });
    const count = await roleDropdowns.count();

    // For admin user, role dropdowns should not be interactive
    // All roles should be displayed as static badges
    for (let i = 0; i < count; i++) {
      const dropdown = roleDropdowns.nth(i);
      // Check if it's inside a Listbox (interactive) or just a badge
      const isDropdown = await dropdown.evaluate((el) => el.getAttribute('type') === 'button');
      if (isDropdown) {
        // This shouldn't happen for admin viewing other members
        expect(false).toBe(true);
      }
    }
  });

  test('MBR-HIERARCHY-002: Admin can remove members but not other admins', async ({ page }) => {
    // Login as admin
    await loginUser(
      page,
      process.env.TEST_ADMIN_EMAIL,
      process.env.TEST_ADMIN_PASSWORD
    );

    await navigateToOrgTeam(page);

    // Find all rows in members table
    const rows = page.locator('tbody tr');
    const rowCount = await rows.count();

    for (let i = 0; i < rowCount; i++) {
      const row = rows.nth(i);
      const roleCell = row.locator('td').nth(1); // Role is typically second column
      const roleText = await roleCell.textContent();
      const actionsCell = row.locator('td').last();
      const removeButton = actionsCell.getByRole('button', { name: /remove member/i });

      if (roleText?.toLowerCase().includes('admin')) {
        // Admin row should NOT have remove button
        await expect(removeButton).not.toBeVisible();
      } else if (roleText?.toLowerCase().includes('owner')) {
        // Owner row should NOT have remove button
        await expect(removeButton).not.toBeVisible();
      }
      // Member rows should have remove button (tested in MBR-REMOVE tests)
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 8: Permission Denied States
// -----------------------------------------------------------------------------

test.describe('MBR-PERM: Permission Denied States', () => {
  const hasMemberCredentials = !!(
    process.env.TEST_MEMBER_EMAIL && process.env.TEST_MEMBER_PASSWORD
  );

  test.skip(
    !hasTestCredentials || !hasMemberCredentials,
    'Skipping: Requires TEST_USER and TEST_MEMBER credentials'
  );

  test('MBR-PERM-001: Member role user cannot invite new members', async ({ page }) => {
    // Login as regular member
    await loginUser(
      page,
      process.env.TEST_MEMBER_EMAIL,
      process.env.TEST_MEMBER_PASSWORD
    );

    await navigateToOrgTeam(page);

    // Invite button should be disabled or show upgrade prompt
    const inviteButton = page.getByRole('button', { name: /invite member/i });
    const hasButton = await inviteButton.isVisible().catch(() => false);

    if (hasButton) {
      // Button should be disabled
      await expect(inviteButton).toBeDisabled();
    }

    // Upgrade prompt may be visible
    const upgradePrompt = page.locator('text=/upgrade|insufficient permissions/i');
    const hasUpgradePrompt = await upgradePrompt.isVisible().catch(() => false);

    // Either button is disabled OR upgrade prompt is shown
    expect(hasButton ? await inviteButton.isDisabled() : hasUpgradePrompt).toBe(true);
  });

  test('MBR-PERM-002: Member role user cannot see remove buttons', async ({ page }) => {
    // Login as regular member
    await loginUser(
      page,
      process.env.TEST_MEMBER_EMAIL,
      process.env.TEST_MEMBER_PASSWORD
    );

    await navigateToOrgTeam(page);

    // Remove buttons should not be visible for member role
    const removeButtons = page.getByRole('button', { name: /remove member/i });
    const count = await removeButtons.count();

    expect(count).toBe(0);
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
 * | MBR-ACCEPT-002  | Unauthenticated Accept redirects to signin         | Critical   | Automated  |
 * | MBR-ACCEPT-003  | Unauthenticated invitee can decline                | High       | Automated  |
 * | MBR-HIERARCHY-001| Admin cannot change member roles                  | Critical   | Automated  |
 * | MBR-HIERARCHY-002| Admin can remove members but not other admins     | Critical   | Automated  |
 * | MBR-PERM-001    | Member role user cannot invite new members         | High       | Automated  |
 * | MBR-PERM-002    | Member role user cannot see remove buttons         | High       | Automated  |
 */
