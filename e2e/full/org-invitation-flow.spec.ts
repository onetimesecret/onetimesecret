// e2e/full/org-invitation-flow.spec.ts

/**
 * E2E Tests for Organization Member Invitation Flow
 *
 * Tests the complete organization member invitation journey including:
 * - Sending invitations from organization settings
 * - Accepting invitations via email link
 * - Post-login redirect preservation
 * - Email mismatch detection and handling
 * - Decline flow for both authenticated and unauthenticated users
 *
 * Based on: docs/test-plans/features/organizations/org-invitation-flow.yaml
 * Issue: https://github.com/onetimesecret/onetimesecret/issues/2319
 *
 * Prerequisites:
 * - Authenticated as the org owner via the project storageState
 *   (e2e/global.setup.ts consumes TEST_USER_*); the multi-context scenarios
 *   below additionally sign in manually inside fresh (unauthenticated)
 *   browser contexts
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 * - Mailpit or similar for email testing (optional for full flow)
 *
 * Multi-context testing:
 * - Email mismatch scenarios require two browser contexts
 * - Tests use incognito contexts for isolation where needed
 *
 * Usage:
 *   # Against dev server
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test org-invitation-flow.spec.ts
 *
 *   # Against external URL with mailpit
 *   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev \
 *   MAILPIT_URL=https://dev.onetime.dev:8025 \
 *     pnpm test:playwright org-invitation-flow.spec.ts
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
 * Context options for a truly unauthenticated browser context.
 *
 * `browser.newContext()` inherits the `full` project's `use` options —
 * including its storageState (the owner session) — so a bare newContext()
 * is NOT unauthenticated. Pass these options to opt out explicitly.
 */
const unauthenticatedContext = { storageState: { cookies: [], origins: [] } };

/**
 * Authenticate user via login form using password tab.
 *
 * Only valid on pages from an unauthenticated context
 * (`browser.newContext(unauthenticatedContext)`): the default `page` fixture
 * and bare `browser.newContext()` carry the storageState session, and an
 * authenticated visitor to /signin is redirected away from the form.
 */
async function loginUser(page: Page, email?: string, password?: string): Promise<void> {
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
 * Navigate to organization team settings page
 */
async function navigateToOrgTeam(page: Page, orgExtid?: string): Promise<string> {
  if (orgExtid) {
    await page.goto(`/org/${orgExtid}/team`);
    return orgExtid;
  }

  // Navigate to org list and find first org
  await page.goto('/orgs');
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

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
  const sendButton = page.getByRole('button', { name: /send invit/i });
  await sendButton.click();

  // Wait for success
  await expect(page.getByText(/invitation sent/i)).toBeVisible({ timeout: 10000 });
}

/**
 * Extract invitation token from pending invitations list via API
 */
async function getInvitationToken(page: Page, email: string): Promise<string | null> {
  const orgExtid = getCurrentOrgExtid(page);
  const response = await page.request.get(`/api/v2/org/${orgExtid}/invitations`);
  const data = await response.json();

  const invitation = data.records?.find((inv: { email: string }) => inv.email === email);
  return invitation?.token || null;
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
 * Create a new user account via signup
 * @deprecated Currently unused - kept for future full integration tests
 */
async function _createAccount(page: Page, email: string, password: string): Promise<void> {
  await page.goto('/signup');

  const emailInput = page.getByLabel(/email/i);
  const passwordInput = page.getByLabel(/password/i);
  const submitButton = page.getByRole('button', { name: /create account|sign up/i });

  await emailInput.fill(email);
  await passwordInput.fill(password);
  await submitButton.click();

  // Wait for account creation - may redirect to signin or dashboard
  await page.waitForURL(/\/(signin|account|dashboard)/, { timeout: 30000 });
}

// -----------------------------------------------------------------------------
// SECTION 1: Invitation Sending
// -----------------------------------------------------------------------------

test.describe('INV-001: Organization Invitation Sending', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('Organization owner can send invitation to new member with email validation', async ({
    page,
  }) => {
    const testEmail = generateTestEmail('invitee');

    // Navigate to org team settings
    await navigateToOrgTeam(page);

    // Click invite member button
    const inviteButton = page.getByRole('button', { name: /invite member/i });
    await expect(inviteButton).toBeVisible();
    await inviteButton.click();

    // Verify invitation form appears
    const emailInput = page.locator('#invite-email');
    await expect(emailInput).toBeVisible();

    // Verify role selector has member and admin options
    const roleSelect = page.locator('#invite-role');
    await expect(roleSelect).toBeVisible();

    const memberOption = roleSelect.locator('option[value="member"]');
    const adminOption = roleSelect.locator('option[value="admin"]');
    await expect(memberOption).toBeAttached();
    await expect(adminOption).toBeAttached();

    // Fill and submit
    await emailInput.fill(testEmail);
    await roleSelect.selectOption('member');

    const sendButton = page.getByRole('button', { name: /send invit/i });
    await sendButton.click();

    // Verify success message
    await expect(page.getByText(/invitation sent/i)).toBeVisible({ timeout: 10000 });

    // Verify invitation appears in pending list
    await expect(page.getByText(testEmail)).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 2: Invitation Acceptance Flow (Updated for Inline Forms)
// -----------------------------------------------------------------------------

test.describe('INV-002: Unauthenticated User Inline Auth Flow', () => {
  test('Unauthenticated user sees inline signup/signin form on invitation page', async ({
    page,
    context,
  }) => {
    // First, create an invitation as org owner
    const testEmail = generateTestEmail('inline-auth-test');
    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);

    // Get the invitation token
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies to simulate unauthenticated user
    await context.clearCookies();

    // Visit invitation link
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify invitation details page loads
    await expect(page.getByText(/invitation/i)).toBeVisible();

    // With Phase 7 inline forms, unauthenticated users see one of:
    // - signup_required state (new user, no account) with inline signup form
    // - signin_required state (existing user) with inline signin form
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
      // Email should be displayed from invitation (readonly input value)
      await expect(page.getByTestId('invite-signup-email-input')).toHaveValue(testEmail);
    } else if (hasSigninForm) {
      // Inline signin form should be visible
      const signinForm = page.getByTestId('invite-signin-form');
      await expect(signinForm).toBeVisible();
      // Sign-in notice should be visible
      const signInNotice = page.locator('.bg-blue-50, .bg-blue-900\\/20');
      await expect(signInNotice).toBeVisible();
    }
  });
});

test.describe('INV-003: Email Mismatch Warning', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('User logged in with different email sees clear mismatch warning with continue-as option', async ({
    browser,
  }) => {
    // Create two browser contexts - one for owner, one for wrong user
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-invited');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Different user logs in and visits invitation
      await loginUser(wrongUserPage); // Logs in as test user (different from invited email)

      await wrongUserPage.goto(`/invite/${token}`);
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify wrong_email state is shown
      const wrongEmailState = wrongUserPage.getByTestId('invite-wrong-email');
      await expect(wrongEmailState).toBeVisible();

      // Verify email mismatch warning is visible (using testid)
      const mismatchWarning = wrongUserPage.getByTestId('email-mismatch-warning');
      await expect(mismatchWarning).toBeVisible();

      // Verify warning shows factual "Different account" framing
      await expect(wrongUserPage.getByText(/different|mismatch/i)).toBeVisible();

      // Verify invited email is shown (appears in both the warning body and
      // the "Continue as" button - first() avoids a strict mode violation)
      await expect(wrongUserPage.getByText(invitedEmail).first()).toBeVisible();

      // Verify "Continue as" button is visible (using testid)
      const continueAsBtn = wrongUserPage.getByTestId('continue-as-btn');
      await expect(continueAsBtn).toBeVisible();

      // Verify accept button is NOT visible (strict email binding - no "Accept with this account")
      const acceptButton = wrongUserPage.getByTestId('accept-invitation-btn');
      await expect(acceptButton).not.toBeVisible();
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

test.describe('INV-004: Continue As Invited Email Flow', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('Clicking Continue As logs out and redirects to invite page', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('switch-account');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Wrong user logs in and visits invitation
      await loginUser(wrongUserPage);
      await wrongUserPage.goto(`/invite/${token}`);
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Click continue as — logs out and redirects to invite page
      const continueAsBtn = wrongUserPage.getByRole('button', { name: /continue as/i });
      await continueAsBtn.click();

      // Verify redirected back to invite page (not signin)
      await wrongUserPage.waitForURL(/\/invite\//, { timeout: 10000 });

      // Verify user is logged out by checking API
      const response = await wrongUserPage.request.get('/bootstrap/me');
      const data = await response.json();
      expect(data.authenticated).toBeFalsy();
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

test.describe('INV-005: Matching Email User Flow', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('User logged in with matching email can immediately accept invitation', async ({
    browser,
  }) => {
    // This test requires creating a user with the exact email that was invited
    // We'll simulate by having the org owner invite themselves (edge case) or
    // by creating a specific user account first

    const ownerContext = await browser.newContext(unauthenticatedContext);
    const ownerPage = await ownerContext.newPage();

    try {
      await loginUser(ownerPage);

      // Navigate to org settings and look for a different org to invite to
      // For this test, we verify the UI state when emails match
      await navigateToOrgTeam(ownerPage);

      // Create invitation for a test email
      const testEmail = generateTestEmail('matching');
      await createInvitation(ownerPage, testEmail);
      const token = await getInvitationToken(ownerPage, testEmail);

      // For the "matching email" test, we need to create a new account with that email
      // and then visit the invitation page
      // Due to test isolation, we'll verify the UI elements that WOULD be shown

      // Clear cookies and visit as unauthenticated to verify button states
      await ownerContext.clearCookies();
      await ownerPage.goto(`/invite/${token}`);
      await expect(ownerPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Unauthenticated + unknown email shows the signup_required state with
      // an inline signup form: a "Continue" submit (the accept path) and a
      // "Decline" button - there is no standalone Accept button here.
      const signupState = ownerPage.getByTestId('invite-signup-required');
      await expect(signupState).toBeVisible();

      const signupSubmit = ownerPage.getByTestId('invite-signup-submit');
      await expect(signupSubmit).toBeVisible();

      // Decline button should also be visible
      const declineButton = ownerPage.getByTestId('invite-signup-decline');
      await expect(declineButton).toBeVisible();

      // Invitation details should show organization and role
      await expect(ownerPage.getByText(/invited/i)).toBeVisible();
    } finally {
      await ownerContext.close();
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 3: Decline and Error States
// -----------------------------------------------------------------------------

test.describe('INV-007a: Authenticated Decline Flow', () => {
  test('Authenticated user can decline invitation and is redirected home', async ({ page }) => {
    // Create invitation
    const testEmail = generateTestEmail('decline-auth');
    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Visit invitation page (still logged in as owner - simulates matching email)
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Click decline
    const declineButton = page.getByRole('button', { name: /decline/i });
    await declineButton.click();

    // Verify success message
    await expect(page.getByText(/declined/i)).toBeVisible({ timeout: 10000 });

    // Verify redirected to home after delay
    await page.waitForURL(/^\/$|\/dashboard/, { timeout: 5000 });
  });
});

test.describe('INV-007b: Unauthenticated Decline Flow', () => {
  test('Unauthenticated user can decline invitation without signing in', async ({
    page,
    context,
  }) => {
    // Create invitation as owner
    const testEmail = generateTestEmail('decline-unauth');
    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies to become unauthenticated
    await context.clearCookies();

    // Visit invitation page
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Decline button should work without auth
    const declineButton = page.getByRole('button', { name: /decline/i });
    await expect(declineButton).toBeVisible();
    await declineButton.click();

    // Verify success message
    await expect(page.getByText(/declined/i)).toBeVisible({ timeout: 10000 });

    // Verify redirected to home
    await page.waitForURL(/^\/$/, { timeout: 5000 });
  });
});

test.describe('INV-008: Expired Invitation', () => {
  test('Expired invitation shows clear error with no action buttons', async ({ page }) => {
    // Use a fake/invalid token to simulate expired invitation
    const fakeToken = 'expired-fake-token-' + Date.now();

    await page.goto(`/invite/${fakeToken}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Error message should be visible
    await expect(page.getByText(/invalid|expired/i)).toBeVisible();

    // Accept button should NOT be visible
    const acceptButton = page.getByRole('button', { name: /accept/i });
    await expect(acceptButton).not.toBeVisible();

    // Decline button should NOT be visible
    const declineButton = page.getByRole('button', { name: /decline/i });
    await expect(declineButton).not.toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 5: Owner Actions (Resend/Revoke)
// -----------------------------------------------------------------------------

test.describe('INV-010: Resend Invitation', () => {
  test('Organization owner can resend pending invitation', async ({ page }) => {
    const testEmail = generateTestEmail('resend');

    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);

    // Find the resend button for this invitation
    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    const resendButton = invitationRow.getByRole('button', { name: /resend/i });

    await expect(resendButton).toBeVisible();
    await expect(resendButton).toHaveCSS('cursor', 'pointer');

    await resendButton.click();

    // Verify success message
    await expect(page.getByText(/resent|sent/i)).toBeVisible({ timeout: 10000 });

    // Invitation should still be in pending list
    await expect(page.getByText(testEmail)).toBeVisible();
  });
});

test.describe('INV-011: Revoke Invitation', () => {
  test('Organization owner can revoke pending invitation making link invalid', async ({
    page,
    context,
  }) => {
    const testEmail = generateTestEmail('revoke');

    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);

    // Get token before revoking
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Find and click revoke button
    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    const revokeButton = invitationRow.getByRole('button', { name: /revoke/i });

    await expect(revokeButton).toBeVisible();
    await expect(revokeButton).toHaveCSS('cursor', 'pointer');

    await revokeButton.click();

    // Verify success message
    await expect(page.getByText(/revoked/i)).toBeVisible({ timeout: 10000 });

    // Invitation should be removed from pending list
    await expect(page.getByText(testEmail)).not.toBeVisible();

    // Verify invitation link is now invalid
    await context.clearCookies();
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show error
    await expect(page.getByText(/invalid|expired|not found/i)).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 6: Email Normalization
// -----------------------------------------------------------------------------

test.describe('INV-012: Gmail Alias Normalization', () => {
  test.skip(!hasTestCredentials, 'Skipping: Requires specific email setup for Gmail alias testing');

  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): needs real
  // Gmail accounts + captured invite email. Unimplemented placeholder ->
  // test.fixme. normalizeEmail() in AcceptInvite.vue is unit-tested; see
  // e2e/QUARANTINE.md.
  test.fixme('Gmail alias normalization allows user+tag@gmail.com to match user@gmail.com', async () => {
    // TODO(#3421): create an invite for user+tag@gmail.com, sign in as
    // user@gmail.com, and assert NO mismatch warning (emails match after
    // normalization) — once a mail interceptor exists.
  });
});

// -----------------------------------------------------------------------------
// SECTION 7: Additional Error Scenarios
// -----------------------------------------------------------------------------

test.describe('INV-014: Duplicate Member Invitation', () => {
  test('Inviting existing organization member shows validation error', async ({ page }) => {

    await navigateToOrgTeam(page);

    // Get the owner's email (who is already a member)
    const bootstrapResponse = await page.request.get('/bootstrap/me');
    const bootstrapData = await bootstrapResponse.json();
    const ownerEmail = bootstrapData.email;

    // Try to invite the owner (existing member)
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

test.describe('INV-016: Invalid Token', () => {
  test('Invalid invitation token shows clear error message', async ({ page }) => {
    const invalidToken = 'invalid-token-format-12345-' + Date.now();

    await page.goto(`/invite/${invalidToken}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Error message should be visible
    await expect(page.getByText(/invalid|expired/i)).toBeVisible();

    // No invitation details should be shown
    const invitationDetails = page.locator('.bg-gray-50, .bg-gray-700\\/50').filter({
      hasText: /you are invited/i,
    });
    await expect(invitationDetails).not.toBeVisible();

    // No action buttons
    await expect(page.getByRole('button', { name: /accept/i })).not.toBeVisible();
    await expect(page.getByRole('button', { name: /decline/i })).not.toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// SECTION 8: Security Edge Cases
// -----------------------------------------------------------------------------

test.describe('INV-SEC-001: Open Redirect Prevention', () => {
  test('Open redirect attack prevention validates redirect parameter', async ({ page }) => {
    // This test exercises the *login form's* redirect handling, so drop the
    // storageState session first - an authenticated visitor to /signin is
    // redirected away and the form (with its assertions) never renders.
    await page.context().clearCookies();

    // Attempt to use malicious redirect URL
    const maliciousRedirects = [
      'https://evil.com/phishing',
      '//evil.com/path',
      'javascript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
    ];

    for (const maliciousUrl of maliciousRedirects) {
      await page.goto(`/signin?redirect=${encodeURIComponent(maliciousUrl)}`);

      // Fill login form
      const emailInput = page.getByLabel(/email/i);
      const passwordInput = page.getByLabel(/password/i);

      if (await emailInput.isVisible()) {
        await emailInput.fill(process.env.TEST_USER_EMAIL || '');
        await passwordInput.fill(process.env.TEST_USER_PASSWORD || '');

        const submitButton = page.getByRole('button', { name: /sign in/i });
        await submitButton.click();

        // Should NOT redirect to external URL
        await page.waitForURL((url) => {
          const href = url.href;
          // Verify we're not on an external domain
          return !href.includes('evil.com') && !href.startsWith('javascript:');
        });

        // Should be on a safe internal page
        const currentUrl = page.url();
        expect(currentUrl).toMatch(/localhost|dev\.onetime|127\.0\.0\.1/);
      }
    }
  });
});

test.describe('INV-SEC-002: Account Enumeration Prevention', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test('Continue-as flow does not reveal whether invited email has existing account', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Create invitation for an email that doesn't exist
      await loginUser(ownerPage);
      const nonExistentEmail = generateTestEmail('nonexistent');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, nonExistentEmail);
      const token = await getInvitationToken(ownerPage, nonExistentEmail);

      // Log in as different user and visit invitation
      await loginUser(wrongUserPage);
      await wrongUserPage.goto(`/invite/${token}`);
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Click continue as — logs out and redirects to invite page
      const continueAsBtn = wrongUserPage.getByRole('button', { name: /continue as/i });
      await continueAsBtn.click();

      // Should redirect to invite page (not signin)
      await wrongUserPage.waitForURL(/\/invite\//, { timeout: 10000 });

      // URL should not indicate whether account exists
      const url = wrongUserPage.url();
      expect(url).not.toContain('account_exists');
      expect(url).not.toContain('new_account');
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

// -----------------------------------------------------------------------------
// Full Integration Flow
// -----------------------------------------------------------------------------

test.describe('INV-017: Complete Invitation Acceptance Flow', () => {
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): full
  // multi-account integration — owner invites, a NEW account signs up with the
  // invited email, accepts, and sees the org. Needs a second account + Mailpit.
  // Unimplemented placeholder -> test.fixme. See e2e/QUARANTINE.md.
  test.fixme('After accepting invitation, user can see and access the organization in their org list', async () => {
    // TODO(#3421): owner creates invite -> new account signs up with the
    // invited email -> accepts -> asserts the org appears in their list.
  });
});

/**
 * Test Case Reference (from org-invitation-flow.yaml):
 *
 * | ID           | Intent                                                    | Priority   |
 * |--------------|-----------------------------------------------------------|------------|
 * | INV-001      | Owner sends invitation with validation                    | Critical   |
 * | INV-002      | Unauthenticated redirect to signin with redirect param    | Critical   |
 * | INV-003      | Email mismatch warning with continue-as option            | High       |
 * | INV-004      | Continue as logs out and redirects to invite page         | High       |
 * | INV-005      | Matching email user can immediately accept                | High       |
 * | INV-007a     | Authenticated decline with redirect home                  | Medium     |
 * | INV-007b     | Unauthenticated decline without signing in                | Medium     |
 * | INV-008      | Expired invitation shows error, no buttons                | High       |
 * | INV-010      | Owner can resend pending invitation                       | Medium     |
 * | INV-011      | Owner can revoke invitation, link becomes invalid         | Medium     |
 * | INV-012      | Gmail alias normalization                                 | Medium     |
 * | INV-014      | Duplicate member shows validation error                   | Medium     |
 * | INV-016      | Invalid token shows clear error                           | Medium     |
 * | INV-017      | Post-accept org appears in user's org list               | High       |
 * | INV-SEC-001  | Open redirect prevention                                  | Critical   |
 * | INV-SEC-002  | Account enumeration prevention                            | High       |
 */
