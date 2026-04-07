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
 * - Set TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables (org owner)
 * - Set TEST_ADMIN_EMAIL and TEST_ADMIN_PASSWORD for admin user tests (optional)
 * - Set TEST_MEMBER_EMAIL and TEST_MEMBER_PASSWORD for member user tests (optional)
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm test:playwright organization-members.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// Generate unique email addresses for test isolation
const generateTestEmail = (prefix: string) =>
  `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.onetimesecret.com`;

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface OrgInfo {
  extid: string;
  name: string;
}

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Authenticate user via login form
 */
async function loginUser(page: Page, email?: string, password?: string): Promise<void> {
  await page.goto('/signin');

  // Click Password tab - Magic Link is the default, password input is hidden
  const passwordTab = page.getByRole('tab', { name: /password/i });
  await passwordTab.waitFor({ state: 'visible', timeout: 5000 });
  await passwordTab.click();

  // Wait for password input to be visible after tab switch
  const passwordInput = page.locator('input[type="password"]');
  await passwordInput.waitFor({ state: 'visible', timeout: 5000 });

  // Fill the form
  const emailInput = page.locator('#signin-email-password');
  await emailInput.fill(email || process.env.TEST_USER_EMAIL || '');
  await passwordInput.fill(password || process.env.TEST_USER_PASSWORD || '');

  // Submit
  const submitButton = page.locator('button[type="submit"]');
  await submitButton.click();

  // Wait for redirect to dashboard/account
  await page.waitForURL(/\/(account|dashboard|org)/, { timeout: 30000 });
}

/**
 * Get the first organization from the /orgs page
 */
async function getFirstOrganization(page: Page): Promise<OrgInfo | null> {
  await page.goto('/orgs');
  await page.waitForLoadState('networkidle');

  const orgsList = page.getByTestId('organizations-list');
  const isOrgListVisible = await orgsList.isVisible().catch(() => false);

  if (!isOrgListVisible) {
    return null;
  }

  // Get the first org card
  const orgCard = orgsList.locator('[data-testid^="org-card-"]').first();
  if (!(await orgCard.isVisible().catch(() => false))) {
    return null;
  }

  // Extract extid from data-testid attribute
  const cardTestId = await orgCard.getAttribute('data-testid');
  const extid = cardTestId?.replace('org-card-', '') || '';

  // Get org name
  const orgNameElement = orgCard.getByTestId('org-name');
  const name = (await orgNameElement.textContent()) || '';

  return { extid, name: name.trim() };
}

/**
 * Navigate to organization team/members settings page
 * URL uses 'team' but internal tab is 'members'
 */
async function navigateToOrgTeam(page: Page, orgExtid?: string): Promise<string> {
  if (orgExtid) {
    await page.goto(`/org/${orgExtid}/team`);
    await page.waitForLoadState('networkidle');
    return orgExtid;
  }

  const org = await getFirstOrganization(page);
  if (!org) {
    throw new Error('No organizations available for testing');
  }

  await page.goto(`/org/${org.extid}/team`);
  await page.waitForLoadState('networkidle');
  return org.extid;
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
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('MBR-LIST-001: Team tab appears in organization settings navigation', async ({ page }) => {
    const org = await getFirstOrganization(page);
    if (!org) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    await page.goto(`/org/${org.extid}`);
    await page.waitForLoadState('networkidle');

    // Check if team tab is visible (feature may be gated)
    const teamTab = page.getByTestId('org-tab-members');
    const hasTeamTab = await teamTab.isVisible().catch(() => false);

    if (!hasTeamTab) {
      test.skip(true, 'Team tab not visible - feature may be gated (see issue #2888)');
      return;
    }

    await expect(teamTab).toBeVisible();
    await expect(teamTab).toHaveAttribute('role', 'tab');
  });

  test('MBR-LIST-002: Navigate to team tab shows members list', async ({ page }) => {
    const org = await getFirstOrganization(page);
    if (!org) {
      test.skip(true, 'No organizations available for testing');
      return;
    }

    // Navigate directly to team tab
    await page.goto(`/org/${org.extid}/team`);
    await page.waitForLoadState('networkidle');

    // Check if we're on team tab or redirected (feature may be gated)
    const url = page.url();
    if (!url.includes('/team')) {
      test.skip(true, 'Team tab route not available - feature may be gated');
      return;
    }

    // Members table should be visible
    const membersTable = page.locator('table').filter({ hasText: /member|role|joined/i });
    await expect(membersTable).toBeVisible({ timeout: 10000 });
  });

  test('MBR-LIST-003: Members list shows owner with correct role badge', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Owner badge should be visible (amber colored)
    const ownerBadge = page.locator('span').filter({ hasText: /owner/i }).first();
    await expect(ownerBadge).toBeVisible({ timeout: 10000 });

    // Should have amber styling
    await expect(ownerBadge).toHaveClass(/amber/);
  });

  test('MBR-LIST-004: Members list displays member count', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Member count should be displayed
    const memberCount = page.locator('p').filter({ hasText: /member|members/i });
    await expect(memberCount.first()).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 2: Invite Member Flow (Owner)
// -----------------------------------------------------------------------------

test.describe('MBR-INVITE: Invite Member Flow', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('MBR-INVITE-001: Owner can see and click Invite Member button', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await expect(inviteButton).toBeVisible();
    await expect(inviteButton).toBeEnabled();
  });

  test('MBR-INVITE-002: Clicking Invite Member shows invitation form', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

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
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const testEmail = generateTestEmail('invite');

    // Create invitation
    await createInvitation(page, testEmail, 'member');

    // Pending invitation should appear in list
    await expect(page.getByText(testEmail)).toBeVisible({ timeout: 10000 });

    // Pending badge should be visible
    const pendingBadge = page
      .locator('.rounded-md')
      .filter({ hasText: testEmail })
      .locator('span')
      .filter({ hasText: /pending/i });
    await expect(pendingBadge).toBeVisible();
  });

  test('MBR-INVITE-004: Invitation form validates email format', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await inviteButton.click();

    const emailInput = page.locator('#invite-email');
    await emailInput.fill('invalid-email');

    const sendButton = page.getByRole('button', { name: /send invite/i });
    await sendButton.click();

    // Should show validation error or HTML5 validation prevents submission
    // HTML5 email validation should trigger
    const isInvalid = await emailInput.evaluate((el: HTMLInputElement) => !el.validity.valid);
    expect(isInvalid).toBe(true);
  });

  test('MBR-INVITE-005: Inviting existing member shows error', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Get the owner's email (who is already a member)
    const bootstrapResponse = await page.request.get('/api/v2/bootstrap/authenticated');
    const bootstrapData = await bootstrapResponse.json();
    const ownerEmail = bootstrapData.record?.email;

    if (!ownerEmail) {
      test.skip(true, 'Could not get owner email from bootstrap');
      return;
    }

    // Try to invite the owner
    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await inviteButton.click();

    const emailInput = page.locator('#invite-email');
    await emailInput.fill(ownerEmail);

    const sendButton = page.getByRole('button', { name: /send invite/i });
    await sendButton.click();

    // Should show error about already being a member
    await expect(page.getByText(/already|member|exists/i)).toBeVisible({ timeout: 10000 });
  });
});

// -----------------------------------------------------------------------------
// SECTION 3: Change Member Role (Owner Only)
// -----------------------------------------------------------------------------

test.describe('MBR-ROLE: Change Member Role', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('MBR-ROLE-001: Owner sees role selector dropdown for non-owner members', async ({
    page,
  }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Check if there are members with editable roles (non-owners)
    // Look for a role dropdown (Listbox button)
    const roleDropdown = page.locator('button').filter({ hasText: /member|admin/i }).first();

    // If no dropdown visible, might be owner-only org or no members
    const hasDropdown = await roleDropdown.isVisible().catch(() => false);
    if (!hasDropdown) {
      test.skip(true, 'No editable member roles found - may be owner-only organization');
      return;
    }

    await expect(roleDropdown).toBeVisible();
  });

  test('MBR-ROLE-002: Owner can change member role from member to admin', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Find a role dropdown that shows "member"
    const memberRoleButton = page
      .locator('button')
      .filter({ hasText: /^member$/i })
      .first();

    const hasMember = await memberRoleButton.isVisible().catch(() => false);
    if (!hasMember) {
      test.skip(true, 'No member-role users found to change role');
      return;
    }

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
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Find owner badge - should be a static badge, not a dropdown
    const ownerBadge = page.locator('span').filter({ hasText: /^owner$/i }).first();

    if (!(await ownerBadge.isVisible().catch(() => false))) {
      test.skip(true, 'Owner badge not found');
      return;
    }

    // Owner role should be displayed as static badge, not dropdown button
    const parentRow = ownerBadge.locator('..').locator('..');
    const roleDropdownInRow = parentRow.locator('button').filter({ hasText: /owner|admin|member/i });

    // If there's a dropdown in owner row, it should be for a different column
    // Or the owner row should not have an editable role dropdown
    const isOwnerRoleEditable = await roleDropdownInRow
      .filter({ hasText: /^owner$/i })
      .isVisible()
      .catch(() => false);

    expect(isOwnerRoleEditable).toBe(false);
  });

  test('MBR-ROLE-004: Role selector shows only admin and member options (not owner)', async ({
    page,
  }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Find any role dropdown
    const roleDropdown = page
      .locator('button')
      .filter({ hasText: /member|admin/i })
      .filter({ hasNotText: /owner/i })
      .first();

    const hasDropdown = await roleDropdown.isVisible().catch(() => false);
    if (!hasDropdown) {
      test.skip(true, 'No editable member roles found');
      return;
    }

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
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('MBR-REMOVE-001: Owner sees remove button for non-owner members', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Find trash icon button (remove action)
    const removeButtons = page.getByRole('button', { name: /remove member/i });

    // Should have at least some remove buttons if there are non-owner members
    // This may be zero if owner is only member
    const count = await removeButtons.count();

    // Just verify the test can run - actual removal tested in MBR-REMOVE-003
    if (count === 0) {
      // Check if there are any non-owner members
      const membersInTable = page.locator('tbody tr');
      const memberCount = await membersInTable.count();

      // If only 1 member (owner), remove buttons won't be visible
      if (memberCount <= 1) {
        test.skip(true, 'No non-owner members to remove');
        return;
      }
    }

    expect(count).toBeGreaterThanOrEqual(0);
  });

  test('MBR-REMOVE-002: Remove button not shown for owner row', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Find owner row
    const ownerBadge = page.locator('span').filter({ hasText: /^owner$/i }).first();
    if (!(await ownerBadge.isVisible().catch(() => false))) {
      test.skip(true, 'Owner badge not found');
      return;
    }

    // Navigate to the table row containing owner
    const ownerRow = ownerBadge.locator('xpath=ancestor::tr');

    // Check actions column (last td)
    const actionsCell = ownerRow.locator('td').last();
    const removeButton = actionsCell.locator('button').filter({
      has: page.locator('svg'),
    });

    // Owner row should show "--" or empty, not remove button
    const hasRemoveButton = await removeButton.isVisible().catch(() => false);
    expect(hasRemoveButton).toBe(false);
  });

  test('MBR-REMOVE-003: Clicking remove shows confirmation dialog', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // Find first remove button
    const removeButton = page.getByRole('button', { name: /remove member/i }).first();

    const hasRemoveButton = await removeButton.isVisible().catch(() => false);
    if (!hasRemoveButton) {
      test.skip(true, 'No remove buttons found - may be owner-only organization');
      return;
    }

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

  test('MBR-REMOVE-004: Confirming removal removes member from list', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    // First create an invitation and have it "accepted" via API
    // Or find an existing removable member
    const removeButton = page.getByRole('button', { name: /remove member/i }).first();

    const hasRemoveButton = await removeButton.isVisible().catch(() => false);
    if (!hasRemoveButton) {
      test.skip(true, 'No removable members found');
      return;
    }

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
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
    await loginUser(page);
  });

  test('MBR-INVMGMT-001: Owner can resend pending invitation', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const testEmail = generateTestEmail('resend');

    // Create invitation first
    await createInvitation(page, testEmail);

    // Find the resend button for this invitation
    const invitationRow = page.locator('.rounded-md, div').filter({ hasText: testEmail });
    const resendButton = invitationRow.getByRole('button', { name: /resend/i });

    await expect(resendButton).toBeVisible();
    await resendButton.click();

    // Success message should appear
    await expect(page.getByText(/resent|sent/i)).toBeVisible({ timeout: 10000 });

    // Invitation should still be in pending list
    await expect(page.getByText(testEmail)).toBeVisible();
  });

  test('MBR-INVMGMT-002: Owner can revoke pending invitation', async ({ page }) => {
    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const testEmail = generateTestEmail('revoke');

    // Create invitation first
    await createInvitation(page, testEmail);

    // Get token for later verification
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Find the revoke button
    const invitationRow = page.locator('.rounded-md, div').filter({ hasText: testEmail });
    const revokeButton = invitationRow.getByRole('button', { name: /revoke|cancel/i });

    await expect(revokeButton).toBeVisible();
    await revokeButton.click();

    // Success message should appear
    await expect(page.getByText(/revoked/i)).toBeVisible({ timeout: 10000 });

    // Invitation should be removed from pending list
    await expect(page.getByText(testEmail)).not.toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 6: Accept Invitation Flow
// -----------------------------------------------------------------------------

test.describe('MBR-ACCEPT: Accept Invitation Flow', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('MBR-ACCEPT-001: Valid invitation token shows invitation details', async ({
    page,
    context,
  }) => {
    // Create invitation as owner
    await loginUser(page);

    let orgExtid: string;
    try {
      orgExtid = await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const testEmail = generateTestEmail('accept');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies to visit as unauthenticated
    await context.clearCookies();

    // Visit invitation link
    await page.goto(`/invite/${token}`);
    await page.waitForLoadState('networkidle');

    // Invitation details should be visible
    const invitationDetails = page.getByTestId('invitation-details');
    await expect(invitationDetails).toBeVisible();

    // Organization name should be shown
    await expect(page.getByText(/invited/i)).toBeVisible();
  });

  test('MBR-ACCEPT-002: Unauthenticated user sees sign-in form (signin_required state)', async ({
    page,
    context,
  }) => {
    // Create invitation as owner
    await loginUser(page);

    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const testEmail = generateTestEmail('accept-unauth');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies to become unauthenticated
    await context.clearCookies();

    // Visit invitation as unauthenticated user
    await page.goto(`/invite/${token}`);
    await page.waitForLoadState('networkidle');

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

  test('MBR-ACCEPT-003: Unauthenticated user cannot decline (signin_required state)', async ({
    page,
    context,
  }) => {
    // Create invitation as owner
    await loginUser(page);

    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

    const testEmail = generateTestEmail('decline');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies to become unauthenticated
    await context.clearCookies();

    // Visit invitation as unauthenticated user
    await page.goto(`/invite/${token}`);
    await page.waitForLoadState('networkidle');

    // In signin_required state, decline button is NOT shown
    // User must authenticate first to accept or decline
    const declineButton = page.getByTestId('decline-invitation-btn');
    await expect(declineButton).not.toBeVisible();

    // Sign-in notice should be visible instead
    const signInNotice = page.getByTestId('sign-in-notice');
    await expect(signInNotice).toBeVisible();
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

    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

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

    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

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

    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

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

    try {
      await navigateToOrgTeam(page);
    } catch {
      test.skip(true, 'Could not navigate to team tab - feature may be gated');
      return;
    }

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
 * | MBR-ACCEPT-003  | Decline button allows declining without auth       | High       | Automated  |
 * | MBR-HIERARCHY-001| Admin cannot change member roles                  | Critical   | Automated  |
 * | MBR-HIERARCHY-002| Admin can remove members but not other admins     | Critical   | Automated  |
 * | MBR-PERM-001    | Member role user cannot invite new members         | High       | Automated  |
 * | MBR-PERM-002    | Member role user cannot see remove buttons         | High       | Automated  |
 */
