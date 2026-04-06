// e2e/full/invitation-email-mismatch-acknowledgment.spec.ts

/**
 * E2E Tests for Invitation Email Mismatch Flow (Strict Email Binding)
 *
 * Phase 4+ Security Change: The acknowledge_email_mismatch flag has been removed.
 * Phase 7 Update: Inline forms on invite page - signup/signin without redirect.
 *
 * Invitations are strictly email-bound - users must switch to the correct account.
 * The wrong_email state shows only a "Switch Account" button, no accept option.
 *
 * Tests the flow when a user logged in with a different email
 * than the invited email attempts to accept an invitation:
 * 1. Email mismatch detection shows wrong_email state
 * 2. Accept button is NOT visible in wrong_email state (strict binding)
 * 3. "Switch Account" triggers logout and redirect to signin
 *
 * Prerequisites:
 * - Set TEST_USER_EMAIL, TEST_USER_PASSWORD environment variables
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test invitation-email-mismatch-acknowledgment.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

// Check if test credentials are configured
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// Generate unique email addresses for test isolation
const generateTestEmail = (prefix: string) =>
  `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.onetimesecret.com`;

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Authenticate user via login form using password tab
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
 * Navigate to organization team settings page
 */
async function navigateToOrgTeam(page: Page, orgExtid?: string): Promise<string> {
  if (orgExtid) {
    await page.goto(`/org/${orgExtid}/team`);
    return orgExtid;
  }

  // Navigate to org list and find first org
  await page.goto('/orgs');
  await page.waitForLoadState('networkidle');

  // Find the first organization link with team tab
  const orgLink = page.locator('a[href*="/org/"]').first();
  const href = await orgLink.getAttribute('href');
  const match = href?.match(/\/org\/([^/]+)/);
  const extractedOrgExtid = match?.[1] || '';

  await page.goto(`/org/${extractedOrgExtid}/team`);
  return extractedOrgExtid;
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
  const sendButton = page.getByRole('button', { name: /send invite/i });
  await sendButton.click();

  // Wait for success
  await expect(page.getByText(/invitation sent/i)).toBeVisible({ timeout: 10000 });
}

/**
 * Get current organization extid from URL
 */
async function getCurrentOrgExtid(page: Page): Promise<string> {
  const url = page.url();
  const match = url.match(/\/org\/([^/]+)/);
  return match?.[1] || '';
}

/**
 * Extract invitation token from pending invitations list via API
 */
async function getInvitationToken(page: Page, email: string): Promise<string | null> {
  const orgExtid = await getCurrentOrgExtid(page);
  const response = await page.request.get(`/api/v2/org/${orgExtid}/invitations`);
  const data = await response.json();

  const invitation = data.records?.find((inv: { email: string }) => inv.email === email);
  return invitation?.token || null;
}

// -----------------------------------------------------------------------------
// SECTION 1: Email Mismatch UI Detection
// -----------------------------------------------------------------------------

test.describe('MISMATCH-001: Email Mismatch Warning Display', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('When logged in with different email, mismatch warning shows Switch Account option only', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext();
    const wrongUserContext = await browser.newContext();

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation for a different email
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-strict');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Different user logs in and visits invitation
      await loginUser(wrongUserPage);
      await wrongUserPage.goto(`/invite/${token}`);
      await wrongUserPage.waitForLoadState('networkidle');

      // Verify email mismatch warning is visible
      const mismatchWarning = wrongUserPage.locator('[data-testid="email-mismatch-warning"]');
      await expect(mismatchWarning).toBeVisible();

      // Verify "Switch Account" button is present
      const switchButton = wrongUserPage.locator('[data-testid="switch-account-btn"]');
      await expect(switchButton).toBeVisible();
      await expect(switchButton).toHaveText(/switch account/i);

      // Verify "Accept with this account" button is NOT present (removed in Phase 4)
      const acceptMismatchButton = wrongUserPage.locator('[data-testid="accept-with-mismatch-btn"]');
      await expect(acceptMismatchButton).not.toBeVisible();
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 2: Accept Button Not Visible in Wrong Email State
// -----------------------------------------------------------------------------

test.describe('MISMATCH-002: Accept Button Hidden When Email Mismatch', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('Accept button is NOT visible when email mismatch exists (strict binding)', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext();
    const wrongUserContext = await browser.newContext();

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-hidden');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);

      // Wrong user visits invitation
      await loginUser(wrongUserPage);
      await wrongUserPage.goto(`/invite/${token}`);
      await wrongUserPage.waitForLoadState('networkidle');

      // Verify wrong_email state is shown
      const wrongEmailState = wrongUserPage.getByTestId('invite-wrong-email');
      await expect(wrongEmailState).toBeVisible();

      // Accept button should NOT be visible in wrong_email state
      // Phase 7 change: The wrong_email state has no accept button at all
      const acceptButton = wrongUserPage.getByTestId('accept-invitation-btn');
      await expect(acceptButton).not.toBeVisible();

      // Only switch account button should be available
      const switchButton = wrongUserPage.getByTestId('switch-account-btn');
      await expect(switchButton).toBeVisible();
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 3: Switch Account Flow
// -----------------------------------------------------------------------------

test.describe('MISMATCH-003: Switch Account Triggers Logout', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('Clicking "Switch Account" logs out user and redirects to signin with email prefilled', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext();
    const wrongUserContext = await browser.newContext();

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-switch');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Wrong user logs in and visits invitation
      await loginUser(wrongUserPage);
      await wrongUserPage.goto(`/invite/${token}`);
      await wrongUserPage.waitForLoadState('networkidle');

      // Click switch account
      const switchButton = wrongUserPage.locator('[data-testid="switch-account-btn"]');
      await switchButton.click();

      // Verify redirected to signin
      await wrongUserPage.waitForURL(/\/signin/, { timeout: 10000 });

      // Verify URL contains email parameter with invited email
      const url = wrongUserPage.url();
      expect(url).toContain('email=');
      // URL should contain the invited email (URL encoded)
      const urlHasInvitedEmail =
        url.includes(encodeURIComponent(invitedEmail)) ||
        url.includes(invitedEmail.replaceAll('@', '%40'));
      expect(urlHasInvitedEmail).toBe(true);

      // Verify URL contains redirect back to invitation
      expect(url).toContain('redirect=');
      expect(url).toContain(token);

      // Verify user is logged out
      const response = await wrongUserPage.request.get('/api/v2/bootstrap/authenticated');
      const data = await response.json();
      expect(data.authenticated || data.record?.authenticated).toBeFalsy();
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 4: No Mismatch - Unauthenticated Flow with Inline Forms
// -----------------------------------------------------------------------------

test.describe('MISMATCH-004: Unauthenticated User Sees Inline Auth Forms', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('When unauthenticated, shows signup or signin inline form (no mismatch)', async ({
    page,
    context,
  }) => {
    await loginUser(page);

    // Get current user's email
    const bootstrapResponse = await page.request.get('/api/v2/bootstrap/authenticated');
    const bootstrapData = await bootstrapResponse.json();
    const currentEmail = bootstrapData.record?.email;
    expect(currentEmail).toBeTruthy();

    // Create invitation for a different test email
    await navigateToOrgTeam(page);
    const testEmail = generateTestEmail('unauthenticated-test');
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);

    // Clear cookies to visit as unauthenticated
    await context.clearCookies();

    // Visit invitation
    await page.goto(`/invite/${token}`);
    await page.waitForLoadState('networkidle');

    // When unauthenticated, no mismatch warning (can't compare emails)
    const mismatchWarning = page.getByTestId('email-mismatch-warning');
    await expect(mismatchWarning).not.toBeVisible();

    // Phase 7: Should see either signup_required or signin_required state
    // with inline forms instead of redirect to signin
    const signupState = page.getByTestId('invite-signup-required');
    const signinState = page.getByTestId('invite-signin-required');

    const hasSignupForm = await signupState.isVisible().catch(() => false);
    const hasSigninForm = await signinState.isVisible().catch(() => false);

    // One of these states should be shown for unauthenticated user
    expect(hasSignupForm || hasSigninForm).toBe(true);

    if (hasSignupForm) {
      // Inline signup form should be visible
      const signupForm = page.getByTestId('invite-signup-form');
      await expect(signupForm).toBeVisible();
    } else if (hasSigninForm) {
      // Inline signin form should be visible
      const signinForm = page.getByTestId('invite-signin-form');
      await expect(signinForm).toBeVisible();
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 5: API Rejects Mismatch
// -----------------------------------------------------------------------------

test.describe('MISMATCH-005: API Rejects Email Mismatch', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('Direct API call with mismatched email returns error', async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const wrongUserContext = await browser.newContext();

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-api');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);

      // Wrong user logs in
      await loginUser(wrongUserPage);

      // Try to accept directly via API (bypassing UI disabled state)
      const response = await wrongUserPage.request.post(`/api/invite/${token}/accept`, {
        data: {},
        headers: { 'Content-Type': 'application/json' },
      });

      // Should be rejected with error
      expect(response.status()).toBeGreaterThanOrEqual(400);

      const data = await response.json();
      expect(data.message).toContain('match');
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });

  test('API rejects even with acknowledge_email_mismatch flag (security change)', async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const wrongUserContext = await browser.newContext();

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-bypass');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);

      // Wrong user logs in
      await loginUser(wrongUserPage);

      // Try to bypass by sending the old acknowledgment flag
      const response = await wrongUserPage.request.post(`/api/invite/${token}/accept`, {
        data: { acknowledge_email_mismatch: true },
        headers: { 'Content-Type': 'application/json' },
      });

      // Should STILL be rejected - flag is now ignored
      expect(response.status()).toBeGreaterThanOrEqual(400);

      const data = await response.json();
      expect(data.message).toContain('match');
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

/**
 * Test Case Reference:
 *
 * | ID            | Intent                                                        | Priority   |
 * |---------------|---------------------------------------------------------------|------------|
 * | MISMATCH-001  | Mismatch warning shows Switch Account only (no Accept option) | High       |
 * | MISMATCH-002  | Accept button disabled when email mismatch exists            | High       |
 * | MISMATCH-003  | Switch account logs out and redirects with email prefill     | High       |
 * | MISMATCH-004  | Unauthenticated shows normal accept flow                      | Medium     |
 * | MISMATCH-005  | API rejects mismatch (even with old acknowledgment flag)     | Critical   |
 */
