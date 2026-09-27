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

import { type BrowserContext, expect, type Page, test } from '@playwright/test';

import {
  closeContexts,
  invitationToken,
  inviteMember,
  openFirstOrgMembersTab,
  openFreshContext,
  signInAsTestUser,
  uniqueTestEmail,
} from '../support/members';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

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
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation for a different email
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('mismatch-strict');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Different user logs in and visits invitation
      await signInAsTestUser(wrongUserPage);
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
      await closeContexts(opened);
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
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('mismatch-hidden');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Wrong user visits invitation
      await signInAsTestUser(wrongUserPage);
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
      await closeContexts(opened);
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
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('mismatch-switch');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Wrong user logs in and visits invitation
      await signInAsTestUser(wrongUserPage);
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
      await closeContexts(opened);
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
    const orgExtid = await openFirstOrgMembersTab(page);
    const testEmail = uniqueTestEmail('unauthenticated-test');
    await inviteMember(page, testEmail);
    const token = await invitationToken(page, orgExtid, testEmail);

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
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('mismatch-api');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Wrong user logs in
      await signInAsTestUser(wrongUserPage);

      // Try to accept directly via API (bypassing the UI, which offers no
      // accept button in the wrong_email state)
      const response = await postAcceptInvite(wrongUserPage, token);

      // Rejected by the email binding, not by CSRF or auth
      expect(response.status()).toBe(422);
      expect(response.headers()['content-type']).toContain('application/json');
      const data = await response.json();
      // API returns { error: "...", error_type: "..." } per ADR-013
      expect(data.error_type).toBe('email_mismatch');
      expect(data.error).toContain('match');

      // And the invitation was not consumed
      await expectInvitationStillPending(ownerPage, token);
    } finally {
      await closeContexts(opened);
    }
  });

  test('API rejects even with acknowledge_email_mismatch flag (security change)', async ({ browser }) => {
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('mismatch-bypass');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Wrong user logs in
      await signInAsTestUser(wrongUserPage);

      // Try to bypass by sending the old acknowledgment flag
      const response = await postAcceptInvite(wrongUserPage, token, {
        acknowledge_email_mismatch: true,
      });

      // Should STILL be rejected by the email binding - flag is now ignored
      expect(response.status()).toBe(422);
      expect(response.headers()['content-type']).toContain('application/json');
      const data = await response.json();
      expect(data.error_type).toBe('email_mismatch');
      expect(data.error).toContain('match');

      // And the invitation was not consumed
      await expectInvitationStillPending(ownerPage, token);
    } finally {
      await closeContexts(opened);
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
