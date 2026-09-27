// e2e/full/invite-token-security.spec.ts

/**
 * E2E Tests for Invite Token Security Regression
 *
 * Guards against email squatting via an unvalidated invite_token.
 *
 * Before the fix: adding invite_token=garbage to ANY signup request
 * suppressed the verification email and signed the new account in, so an
 * attacker could claim an arbitrary email address without proving they own
 * it.
 *
 * Now: when a signup carries an invite_token, the create-account hook in
 * apps/web/auth/config/hooks/account.rb looks the invitation up before any
 * account or customer row is written. Unless the token names a pending,
 * unexpired invitation for the signup email, the signup is refused (HTTP
 * 400) and nothing is created, so there is no account to sign in or to
 * verify. A valid token lets the signup through and signs the new account in.
 *
 * Test scenarios:
 * - SEC-INV-001: Garbage invite_token is refused and grants no session
 * - SEC-INV-002: Garbage invite_token creates no account
 * - SEC-INV-003: Valid invite_token DOES sign the new account in
 * - SEC-INV-004: Direct API POSTs with garbage, empty and UUID-shaped tokens
 * - SEC-INV-005: Invite page with a garbage token shows the invalid state
 *
 * Prerequisites:
 * - Authenticated as the org owner via the project storageState
 *   (e2e/global.setup.ts consumes TEST_USER_*); it sends the invitation in
 *   SEC-INV-003 and never accepts it, so its org gains no member
 * - Full auth mode with accounts that can sign in without verifying their
 *   email (the full lane sets AUTH_VERIFY_ACCOUNT_ENABLED=false): SEC-INV-002
 *   signs in to prove an account exists
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test invite-token-security.spec.ts
 */

import { expect, type APIResponse, type BrowserContext, type Page, test } from '@playwright/test';

import {
  closeContexts,
  generatePassword,
  invitationToken,
  inviteMember,
  openFirstOrgMembersTab,
  openFreshContext,
  submitInviteSignup,
  uniqueTestEmail,
} from '../support/members';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Get a valid CSRF token from the server.
 *
 * The Rack::Protection::AuthenticityToken middleware validates CSRF tokens
 * on POST requests. The server returns a masked token in the X-CSRF-Token
 * response header. We need to capture this and send it back as the `shrimp`
 * parameter or X-CSRF-Token header on subsequent POSTs.
 */
async function getCsrfToken(page: Page): Promise<string> {
  // Make a GET request to establish a session and receive a CSRF token
  const response = await page.request.get('/');
  const csrfToken = response.headers()['x-csrf-token'] || '';
  expect(csrfToken, 'GET / returns a CSRF token').toBeTruthy();
  return csrfToken;
}

/**
 * POST a Rodauth JSON form with the CSRF token both as the `shrimp` body
 * param (for Rodauth) and the `X-CSRF-Token` header (for Rack::Protection).
 */
async function postAuthForm(
  page: Page,
  path: '/auth/create-account' | '/auth/login',
  data: Record<string, string>
): Promise<APIResponse> {
  const csrfToken = await getCsrfToken(page);
  return page.request.post(path, {
    data: { ...data, shrimp: csrfToken },
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken,
    },
  });
}

/** Sign up through the Rodauth JSON API, with an invite_token when given. */
function createAccountViaAPI(
  page: Page,
  email: string,
  password: string,
  inviteToken?: string
): Promise<APIResponse> {
  const data: Record<string, string> = { login: email, password };
  if (inviteToken !== undefined) data.invite_token = inviteToken;
  return postAuthForm(page, '/auth/create-account', data);
}

/** Sign in through the Rodauth JSON API. */
function loginViaAPI(page: Page, email: string, password: string): Promise<APIResponse> {
  return postAuthForm(page, '/auth/login', { login: email, password });
}

/** Whether the page's session is signed in, as /bootstrap/me reports it. */
async function isAuthenticated(page: Page): Promise<boolean> {
  const response = await page.request.get('/bootstrap/me');
  expect(response.ok(), 'GET /bootstrap/me').toBe(true);
  const data = await response.json();
  return Boolean(data.authenticated);
}

/** A signup with an invite_token that names no invitation is refused. */
async function expectSignupRefused(response: APIResponse, token: string): Promise<void> {
  expect(response.status(), `create-account with invite_token=${token}`).toBe(400);
}

// -----------------------------------------------------------------------------
// SEC-INV-001: Garbage invite_token does NOT auto-login
// -----------------------------------------------------------------------------

test.describe('SEC-INV-001: Garbage invite_token does NOT auto-login', () => {
  test('signup with garbage invite_token is refused and leaves user unauthenticated', async ({
    page,
  }) => {
    // The full project starts authenticated via storageState; this scenario
    // asserts an *unauthenticated* outcome, so drop that session first.
    await page.context().clearCookies();

    const garbageToken = 'nonexistent_garbage_token_' + Date.now();
    const response = await createAccountViaAPI(
      page,
      uniqueTestEmail('garbage-token'),
      'TestPassword123!',
      garbageToken
    );

    await expectSignupRefused(response, garbageToken);
    // SECURITY ASSERTION: garbage token must NOT grant authenticated session
    expect(await isAuthenticated(page)).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// SEC-INV-002: Garbage invite_token creates no account
// -----------------------------------------------------------------------------

test.describe('SEC-INV-002: Garbage invite_token creates no account', () => {
  test('signup with garbage invite_token leaves no account to sign in to or verify', async ({
    page,
  }) => {
    // The original risk was an account whose email verification the token
    // suppressed. The hook now refuses the signup before writing any row, so
    // the check is that no account exists. The lane signs accounts in
    // without verification, so a sign-in shows whether one exists.
    await page.context().clearCookies();

    const email = uniqueTestEmail('verify-not-suppressed');
    const password = generatePassword();
    const garbageToken = 'fake_token_should_not_suppress_' + Date.now();

    await expectSignupRefused(
      await createAccountViaAPI(page, email, password, garbageToken),
      garbageToken
    );

    const refusedLogin = await loginViaAPI(page, email, password);
    expect(refusedLogin.ok(), 'sign-in to the refused signup').toBe(false);
    expect(await isAuthenticated(page)).toBe(false);

    // Control: the same address signs up and signs in without a token, so
    // the refusal above came from the token, not from the address or from
    // the request shape.
    const signup = await createAccountViaAPI(page, email, password);
    expect(signup.status(), 'create-account without invite_token').toBe(200);
    const login = await loginViaAPI(page, email, password);
    expect(login.status(), 'sign-in after a plain signup').toBe(200);
    expect(await isAuthenticated(page)).toBe(true);
  });
});

// -----------------------------------------------------------------------------
// SEC-INV-003: Valid invite_token DOES auto-login (regression guard)
// -----------------------------------------------------------------------------

test.describe('SEC-INV-003: Valid invite_token auto-login works', () => {
  test('signup with valid invite_token signs the new account in', async ({ page, browser }) => {
    const opened: BrowserContext[] = [];
    try {
      // The storageState owner sends the invitation. The invitee only signs
      // up and never accepts, so the owner's org gains no member.
      const extid = await openFirstOrgMembersTab(page);
      const invitedEmail = uniqueTestEmail('valid-token-autologin');
      await inviteMember(page, invitedEmail);
      const token = await invitationToken(page, extid, invitedEmail);

      // The invitee opens the link with no session and signs up inline.
      const invitee = await (await openFreshContext(browser, opened)).newPage();
      await invitee.goto(`/invite/${token}`);
      await expect(invitee.getByTestId('invite-signup-required')).toBeVisible();
      await expect(invitee.getByTestId('invite-signup-email-input')).toHaveValue(invitedEmail);
      expect(await isAuthenticated(invitee)).toBe(false);

      await submitInviteSignup(invitee, generatePassword());

      // The valid token signs the new account in, so the page recomputes to
      // the direct_accept confirmation. The invitation itself stays pending
      // until the explicit Accept click.
      await expect(invitee.getByTestId('invite-direct-accept')).toBeVisible({ timeout: 15_000 });
      expect(await isAuthenticated(invitee)).toBe(true);
    } finally {
      await closeContexts(opened);
    }
  });
});

// -----------------------------------------------------------------------------
// SEC-INV-004: Direct API attack - garbage token via POST
// -----------------------------------------------------------------------------

test.describe('SEC-INV-004: Direct API attack with garbage invite_token', () => {
  test('POST to /auth/create-account with garbage invite_token does not grant a session', async ({
    page,
  }) => {
    // The full project starts authenticated via storageState; this scenario
    // simulates an *anonymous* attacker, so drop that session first.
    await page.context().clearCookies();

    // Simulate the attack: POST directly with garbage invite_token. This
    // bypasses any UI validation and hits the Rodauth hooks directly.
    const attackToken = 'ATTACK_TOKEN_' + Date.now();
    const response = await createAccountViaAPI(
      page,
      uniqueTestEmail('api-attack'),
      'TestPassword123!',
      attackToken
    );

    await expectSignupRefused(response, attackToken);
    // SECURITY ASSERTION: garbage token must NOT grant authenticated session
    expect(await isAuthenticated(page)).toBe(false);

    // Also verify: if we try to access protected resources, we're denied
    const protectedResponse = await page.request.get('/api/account', {
      headers: { Accept: 'application/json' },
    });
    expect([401, 403, 302, 404]).toContain(protectedResponse.status());
  });

  test('POST to /auth/create-account with empty invite_token behaves normally', async ({
    page,
  }) => {
    // Anonymous-visitor scenario: drop the storageState session first.
    await page.context().clearCookies();

    // An empty invite_token is treated like no token at all: the account is
    // created, and a plain signup does not sign it in.
    const response = await createAccountViaAPI(
      page,
      uniqueTestEmail('empty-token'),
      'TestPassword123!',
      ''
    );

    expect(response.status(), 'create-account with an empty invite_token').toBe(200);
    expect(await isAuthenticated(page)).toBe(false);
  });

  test('POST to /auth/create-account with UUID-shaped fake token does not grant a session', async ({
    page,
  }) => {
    // Anonymous-visitor scenario: drop the storageState session first.
    await page.context().clearCookies();

    // UUID-shaped token that doesn't correspond to any real invitation.
    // This tests the find_by_token lookup returning nil.
    const fakeUuid = '550e8400-e29b-41d4-a716-446655440000';
    const response = await createAccountViaAPI(
      page,
      uniqueTestEmail('uuid-fake-token'),
      'TestPassword123!',
      fakeUuid
    );

    await expectSignupRefused(response, fakeUuid);
    expect(await isAuthenticated(page)).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// SEC-INV-005: UI flow - garbage token on invite page shows invalid state
// -----------------------------------------------------------------------------

test.describe('SEC-INV-005: Invite page with garbage token', () => {
  test('visiting /invite/garbage-token shows invalid state with no auth forms', async ({
    page,
  }) => {
    // The final assertion checks an anonymous visitor stays unauthenticated,
    // so drop the storageState session first.
    await page.context().clearCookies();

    const garbageToken = 'garbage_security_test_' + Date.now();

    await page.goto(`/invite/${garbageToken}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show the invalid state
    const invalidState = page.getByTestId('invite-invalid');
    await expect(invalidState).toBeVisible();

    // Error message should indicate invalid/expired token
    await expect(page.getByText(/invalid|expired|not found/i)).toBeVisible();

    // No signup or signin forms should be visible (can't use a garbage token)
    const signupForm = page.getByTestId('invite-signup-form');
    const signinForm = page.getByTestId('invite-signin-form');
    await expect(signupForm).not.toBeVisible();
    await expect(signinForm).not.toBeVisible();

    // No accept/decline buttons should be shown
    const acceptButton = page.getByTestId('accept-invitation-btn');
    const declineButton = page.getByTestId('decline-invitation-btn');
    await expect(acceptButton).not.toBeVisible();
    await expect(declineButton).not.toBeVisible();

    // User should NOT be authenticated
    const authResponse = await page.request.get('/bootstrap/me');
    const authData = await authResponse.json();
    expect(authData.authenticated).toBeFalsy();
  });
});

/**
 * Test Case Reference:
 *
 * | ID           | Intent                                                           | Priority   |
 * |--------------|------------------------------------------------------------------|------------|
 * | SEC-INV-001  | Garbage invite_token is refused and grants no session            | Critical   |
 * | SEC-INV-002  | Garbage invite_token creates no account (nothing to verify)      | Critical   |
 * | SEC-INV-003  | Valid invite_token DOES sign the new account in (regression)     | Critical   |
 * | SEC-INV-004  | Direct API POST with garbage/empty/UUID token denied session     | Critical   |
 * | SEC-INV-005  | Invite page with garbage token shows invalid state               | High       |
 *
 * Security context:
 * These tests guard the fix for email squatting via an unvalidated
 * invite_token. Before the fix, appending invite_token=garbage to any signup
 * suppressed the verification email and signed the user in, bypassing email
 * ownership verification entirely.
 *
 * The create-account hook (apps/web/auth/config/hooks/account.rb) now checks
 * a supplied token before creating anything:
 *   1. Token exists (OrganizationMembership.find_by_token)
 *   2. Invitation is pending (not already accepted/declined/revoked)
 *   3. Invitation is not expired
 *   4. Signup email matches invited email (normalized comparison)
 *
 * If ANY check fails, the signup is refused and no account is written. An
 * empty token counts as no token.
 */
