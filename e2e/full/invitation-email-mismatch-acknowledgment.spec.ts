// e2e/full/invitation-email-mismatch-acknowledgment.spec.ts

/**
 * E2E Tests for Invitation Email Mismatch Flow (Strict Email Binding)
 *
 * Phase 4+ Security Change: The acknowledge_email_mismatch flag has been removed.
 * Phase 7 Update: Inline forms on invite page - signup/signin without redirect.
 *
 * Invitations are strictly email-bound - users must continue as the invited email.
 * The wrong_email state shows a "Continue as" button and a decline option.
 *
 * Tests the flow when a user logged in with a different email
 * than the invited email attempts to accept an invitation:
 * 1. Email mismatch detection shows wrong_email state
 * 2. Accept button is NOT visible in wrong_email state (strict binding)
 * 3. "Continue as" triggers logout and redirect to invite page
 *
 * Prerequisites:
 * - Authenticated as the org owner via the project storageState
 *   (e2e/global.setup.ts consumes TEST_USER_* and fails without them);
 *   multi-context scenarios sign the same owner in again inside fresh
 *   (unauthenticated) browser contexts. The owner's own email differs from
 *   every generated invite email, so the owner is the "wrong" user.
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test invitation-email-mismatch-acknowledgment.spec.ts
 */

import { expect, Page, test } from '@playwright/test';

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
 * Get current organization extid from URL
 */
function getCurrentOrgExtid(page: Page): string {
  const url = page.url();
  const match = url.match(/\/org\/([^/]+)/);
  return match?.[1] || '';
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

/**
 * Get a CSRF token bound to the page's session.
 *
 * Rack::Protection rejects a POST without one (403 text/plain) before any
 * route logic runs, so a raw API call must send it to reach the endpoint.
 * Same approach as e2e/full/invite-token-security.spec.ts.
 */
async function getCsrfToken(page: Page): Promise<string> {
  const response = await page.request.get('/');
  const csrfToken = response.headers()['x-csrf-token'] || '';
  expect(csrfToken, 'server did not return an X-CSRF-Token header').toBeTruthy();
  return csrfToken;
}

/**
 * POST /api/invite/:token/accept as the page's session, with CSRF, so the
 * request reaches AcceptInvite and its email-binding check.
 */
async function postAcceptInvite(page: Page, token: string, body: Record<string, unknown> = {}) {
  const csrfToken = await getCsrfToken(page);
  return page.request.post(`/api/invite/${token}/accept`, {
    data: { ...body, shrimp: csrfToken },
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken,
    },
  });
}

/**
 * Assert the invitation is still pending and actionable (nobody accepted it).
 */
async function expectInvitationStillPending(page: Page, token: string): Promise<void> {
  const response = await page.request.get(`/api/invite/${token}`);
  expect(response.ok()).toBe(true);
  const data = await response.json();
  expect(data.record.status).toBe('pending');
  expect(data.record.actionable).toBe(true);
}

// -----------------------------------------------------------------------------
// SECTION 1: Email Mismatch UI Detection
// -----------------------------------------------------------------------------

test.describe('MISMATCH-001: Email Mismatch Warning Display', () => {
  test('When logged in with different email, mismatch warning shows Continue As option', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

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
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify email mismatch warning is visible
      const mismatchWarning = wrongUserPage.locator('[data-testid="email-mismatch-warning"]');
      await expect(mismatchWarning).toBeVisible();

      // Verify "Continue as" button is present
      const continueAsBtn = wrongUserPage.locator('[data-testid="continue-as-btn"]');
      await expect(continueAsBtn).toBeVisible();
      await expect(continueAsBtn).toHaveText(/continue as/i);

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
  test('Accept button is NOT visible when email mismatch exists (strict binding)', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

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
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify wrong_email state is shown
      const wrongEmailState = wrongUserPage.getByTestId('invite-wrong-email');
      await expect(wrongEmailState).toBeVisible();

      // Accept button should NOT be visible in wrong_email state
      // Phase 7 change: The wrong_email state has no accept button at all
      const acceptButton = wrongUserPage.getByTestId('accept-invitation-btn');
      await expect(acceptButton).not.toBeVisible();

      // Continue-as button should be available
      const continueAsBtn = wrongUserPage.getByTestId('continue-as-btn');
      await expect(continueAsBtn).toBeVisible();
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 3: Continue As Flow
// -----------------------------------------------------------------------------

test.describe('MISMATCH-003: Continue As Triggers Logout', () => {
  test('Clicking "Continue as" logs out user and redirects to invite page', async ({
    browser,
  }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

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
      await expect(wrongUserPage.getByTestId('invite-wrong-email')).toBeVisible();

      // Click continue as — POSTs /auth/logout, then hard-navigates back to
      // the same /invite/:token URL. The URL never changes, so waiting on it
      // proves nothing; wait on the logout response and the reloaded state.
      const logoutResponse = wrongUserPage.waitForResponse(
        (res) =>
          res.request().method() === 'POST' && new URL(res.url()).pathname === '/auth/logout'
      );
      await wrongUserPage.getByTestId('continue-as-btn').click();
      expect((await logoutResponse).ok()).toBe(true);

      // Back on the invite page (not signin), now rendered for an anonymous
      // visitor: the unauthenticated default is signup_required.
      await expect(wrongUserPage).toHaveURL(new RegExp(`/invite/${token}$`));
      await expect(wrongUserPage.getByTestId('invite-signup-required')).toBeVisible();
      await expect(wrongUserPage.getByTestId('invite-wrong-email')).toBeHidden();

      // The server agrees the session is gone
      const response = await wrongUserPage.request.get('/bootstrap/me');
      const data = await response.json();
      expect(data.authenticated).toBeFalsy();
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
  test('When unauthenticated, shows signup or signin inline form (no mismatch)', async ({
    page,
    context,
  }) => {
    // Get the current (storageState) user's email
    const bootstrapResponse = await page.request.get('/bootstrap/me');
    const bootstrapData = await bootstrapResponse.json();
    const currentEmail = bootstrapData.email;
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
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Phase 7: inline forms instead of a redirect to signin. signup_required
    // is the unauthenticated default (the API never discloses whether an
    // account exists, AZ7/#3856); signin_required only appears after a
    // signup attempt comes back signup_unavailable.
    await expect(page.getByTestId('invite-signup-required')).toBeVisible();
    await expect(page.getByTestId('invite-signup-form')).toBeVisible();
    await expect(page.getByTestId('invite-signup-email-input')).toHaveValue(testEmail);

    // When unauthenticated, no mismatch warning (can't compare emails).
    // Checked after the state rendered, so it cannot pass during loading.
    await expect(page.getByTestId('email-mismatch-warning')).toBeHidden();
  });
});

// -----------------------------------------------------------------------------
// SECTION 5: API Rejects Mismatch
// -----------------------------------------------------------------------------

test.describe('MISMATCH-005: API Rejects Email Mismatch', () => {
  test('Direct API call with mismatched email returns error', async ({ browser }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-api');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Wrong user logs in
      await loginUser(wrongUserPage);

      // Try to accept directly via API (bypassing the UI, which offers no
      // accept button in the wrong_email state)
      const response = await postAcceptInvite(wrongUserPage, token!);

      // Rejected by the email binding, not by CSRF or auth
      expect(response.status()).toBe(422);
      expect(response.headers()['content-type']).toContain('application/json');
      const data = await response.json();
      // API returns { error: "...", error_type: "..." } per ADR-013
      expect(data.error_type).toBe('email_mismatch');
      expect(data.error).toContain('match');

      // And the invitation was not consumed
      await expectInvitationStillPending(ownerPage, token!);
    } finally {
      await ownerContext.close();
      await wrongUserContext.close();
    }
  });

  test('API rejects even with acknowledge_email_mismatch flag (security change)', async ({ browser }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('mismatch-bypass');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Wrong user logs in
      await loginUser(wrongUserPage);

      // Try to bypass by sending the old acknowledgment flag
      const response = await postAcceptInvite(wrongUserPage, token!, {
        acknowledge_email_mismatch: true,
      });

      // Should STILL be rejected by the email binding - flag is now ignored
      expect(response.status()).toBe(422);
      expect(response.headers()['content-type']).toContain('application/json');
      const data = await response.json();
      expect(data.error_type).toBe('email_mismatch');
      expect(data.error).toContain('match');

      // And the invitation was not consumed
      await expectInvitationStillPending(ownerPage, token!);
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
 * | MISMATCH-001  | Mismatch warning shows Continue As option (no Accept option) | High       |
 * | MISMATCH-002  | Accept button disabled when email mismatch exists            | High       |
 * | MISMATCH-003  | Continue as logs out and redirects to invite page            | High       |
 * | MISMATCH-004  | Unauthenticated shows normal accept flow                      | Medium     |
 * | MISMATCH-005  | API rejects mismatch (even with old acknowledgment flag)     | Critical   |
 */
