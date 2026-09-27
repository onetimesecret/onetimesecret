// e2e/full/invite-flow-states.spec.ts

/**
 * E2E Tests for Invite Flow States (Phase 7 Implementation)
 *
 * Tests the invite flow state machine (src/apps/session/views/AcceptInvite.vue):
 * - loading: Initial fetch in progress
 * - signup_required: Unauthenticated default (the API never discloses whether
 *   an account exists, AZ7/#3856)
 * - signin_required: Unauthenticated, after a signup attempt came back
 *   signup_unavailable (the invited email already has an account)
 * - direct_accept: Authenticated with correct email, can accept immediately
 * - wrong_email: Authenticated but with different email than invitation
 * - already_accepted: Invitation was already accepted (status: active)
 * - invalid: Invitation is expired, declined, revoked, or doesn't exist
 *
 * The new atomic signup+accept flow:
 * - Inline signup/signin forms on the invite page
 * - Account created + invite accepted in one action
 * - Strict email binding (no acknowledge_email_mismatch option)
 *
 * Prerequisites:
 * - Authenticated as the org owner via the project storageState
 *   (e2e/global.setup.ts consumes TEST_USER_* and fails without them);
 *   multi-context scenarios sign in manually inside fresh (unauthenticated)
 *   browser contexts
 * - Full auth mode with accounts that can sign in without verifying their
 *   email (the full lane sets AUTH_VERIFY_ACCOUNT_ENABLED=false): the
 *   accept journeys sign up throwaway accounts in-test
 * - Application running locally or PLAYWRIGHT_BASE_URL set
 *
 * Isolation: every journey that ACCEPTS an invitation uses a throwaway owner
 * (signUpAndSignIn) as the inviter, so the shared storageState owner's org
 * never gains a member and its account never joins a second org.
 *
 * Usage:
 *   TEST_USER_EMAIL=owner@example.com TEST_USER_PASSWORD=secret \
 *     pnpm playwright test invite-flow-states.spec.ts
 */

import { Browser, BrowserContext, expect, Page, test } from '@playwright/test';

// Generate unique email addresses for test isolation
const generateTestEmail = (prefix: string) =>
  `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.onetimesecret.com`;

// Passwords for throwaway accounts created in-test
const generatePassword = () => `Inv-${Math.random().toString(36).slice(2, 10)}-Pw123!`;

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
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
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
  await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
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
 * Register a new password account through the signup form.
 *
 * Only valid on a page from an unauthenticated context. Leaves the page on
 * /check-email and the context signed out; the lane creates accounts that can
 * sign in without verifying their email.
 */
async function signUpAccount(page: Page, email: string, password: string): Promise<void> {
  await page.goto('/signup');
  await expect(page.getByTestId('signup-form')).toBeVisible();
  await page.getByTestId('signup-email-input').fill(email);
  await page.getByTestId('signup-password-input').fill(password);
  await page.getByTestId('signup-terms-checkbox').check();
  await page.getByTestId('signup-submit').click();

  // A fresh email must be accepted; signup hashes the password server-side.
  await expect(page.getByTestId('check-email-view')).toBeVisible({ timeout: 15000 });
}

interface SignedInAccount {
  page: Page;
  email: string;
}

/**
 * Open an unauthenticated context and register it in `opened`, so the
 * test's finally block closes it even when a later step throws.
 */
async function openContext(browser: Browser, opened: BrowserContext[]): Promise<BrowserContext> {
  const context = await browser.newContext(unauthenticatedContext);
  opened.push(context);
  return context;
}

/**
 * Sign up a throwaway account in its own unauthenticated context and sign it
 * in. Its default workspace makes it an org owner that can send invitations.
 */
async function signUpAndSignIn(
  browser: Browser,
  opened: BrowserContext[],
  prefix: string
): Promise<SignedInAccount> {
  const context = await openContext(browser, opened);
  const page = await context.newPage();
  const email = generateTestEmail(prefix);
  const password = generatePassword();

  await signUpAccount(page, email, password);
  await loginUser(page, email, password);

  return { page, email };
}

/**
 * Assert, as the org owner, that `email` is now an active member of the org.
 */
async function expectMember(
  ownerPage: Page,
  orgExtid: string,
  email: string,
  role: 'member' | 'admin' = 'member'
): Promise<void> {
  const response = await ownerPage.request.get(`/api/organizations/${orgExtid}/members`);
  expect(response.ok()).toBe(true);
  const data = await response.json();
  const member = data.records?.find((m: { email: string }) => m.email === email);
  expect(member, `${email} is not a member of ${orgExtid}`).toBeTruthy();
  expect(member.role).toBe(role);
}

/**
 * Fill and submit the inline invite signup form (signup_required state).
 */
async function submitInviteSignup(page: Page, password: string): Promise<void> {
  await page.getByTestId('invite-signup-password-input').fill(password);
  await page.getByTestId('invite-signup-confirm-password-input').fill(password);
  await page.getByTestId('invite-signup-terms-checkbox').check();
  await page.getByTestId('invite-signup-submit').click();
}

/**
 * Accept from the direct_accept state and wait for the join to complete.
 *
 * After the accepted state the view pushes to /orgs; a member who owns no
 * org is sent on to /dashboard by the owner-only /orgs guard, so assert only
 * that the invite page is left.
 */
async function acceptDirectly(page: Page): Promise<void> {
  await expect(page.getByTestId('invite-direct-accept')).toBeVisible({ timeout: 15000 });
  await page.getByTestId('accept-invitation-btn').click();
  await expect(page.getByTestId('invite-accepted')).toBeVisible();
  await expect(page.getByTestId('invite-accepted')).toContainText(
    'Invitation accepted successfully'
  );
  await expect(page).not.toHaveURL(/\/invite\//, { timeout: 10000 });
}

// -----------------------------------------------------------------------------
// INV-001: New User Signup via Invite with Password
// -----------------------------------------------------------------------------

test.describe('INV-001: New User Atomic Signup Flow', () => {
  test('new user can signup and join organization atomically', async ({ browser }) => {
    const opened: BrowserContext[] = [];

    try {
      // A throwaway owner invites, so the new member joins its org, not the
      // shared storageState owner's.
      const owner = await signUpAndSignIn(browser, opened, 'inv001-owner');
      const orgExtid = await navigateToOrgTeam(owner.page);
      const invitedEmail = generateTestEmail('new-user-signup');
      await createInvitation(owner.page, invitedEmail);
      const token = await getInvitationToken(owner.page, invitedEmail);
      expect(token).toBeTruthy();

      // New user (no account, not signed in) opens the invitation
      const page = await (await openContext(browser, opened)).newPage();
      await page.goto(`/invite/${token}`);

      // signup_required is the unauthenticated default, with the invited
      // email prefilled (readonly) in the inline signup form
      await expect(page.getByTestId('invite-signup-required')).toBeVisible();
      await expect(page.getByTestId('invite-signup-form')).toBeVisible();
      await expect(page.getByTestId('invite-signup-email-input')).toHaveValue(invitedEmail);

      // Signup establishes the session but does NOT accept the invitation:
      // the state machine recomputes to direct_accept and the user confirms
      // the join with the explicit Accept button (AcceptInvite.onAuthSuccess).
      await submitInviteSignup(page, generatePassword());
      await acceptDirectly(page);

      // The owner now sees the new user in the org
      await expectMember(owner.page, orgExtid, invitedEmail);
    } finally {
      await Promise.all(opened.map((context) => context.close()));
    }
  });
});

// -----------------------------------------------------------------------------
// INV-002: New User Magic Link (Skipped - Requires Feature Flag)
// -----------------------------------------------------------------------------

test.describe('INV-002: New User Magic Link Flow', () => {
  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): the magic
  // link arrives by email, so this needs a mail interceptor the CI container
  // does not run. Unimplemented placeholder -> test.fixme. See e2e/QUARANTINE.md.
  test.fixme('new user can join via magic link', async () => {
    // TODO(#3421): drive the magic-link join once a mail interceptor exists.
  });
});

// -----------------------------------------------------------------------------
// INV-003: New User SSO (Skipped - Requires SSO Configuration)
// -----------------------------------------------------------------------------

test.describe('INV-003: New User SSO Flow', () => {
  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): needs an
  // SSO/IdP configured AND a captured invite email. Unimplemented placeholder
  // -> test.fixme. See e2e/QUARANTINE.md.
  test.fixme('new user can join via SSO', async () => {
    // TODO(#3421): drive the SSO join once an IdP + mail interceptor exist.
  });
});

// -----------------------------------------------------------------------------
// INV-004: Existing User Signin and Accept
// -----------------------------------------------------------------------------

test.describe('INV-004: Existing User Signin Flow', () => {
  test('existing user can signin and accept invitation', async ({ browser }) => {
    const opened: BrowserContext[] = [];

    try {
      const owner = await signUpAndSignIn(browser, opened, 'inv004-owner');
      const orgExtid = await navigateToOrgTeam(owner.page);

      // The invited email already has an account; its owner is signed out
      const inviteePage = await (await openContext(browser, opened)).newPage();
      const invitedEmail = generateTestEmail('existing-user');
      const password = generatePassword();
      await signUpAccount(inviteePage, invitedEmail, password);

      await createInvitation(owner.page, invitedEmail);
      const token = await getInvitationToken(owner.page, invitedEmail);
      expect(token).toBeTruthy();

      await inviteePage.goto(`/invite/${token}`);

      // The page cannot know the account exists (AZ7/#3856), so it offers
      // signup first; the backend answers signup_unavailable and the view
      // falls back to the inline signin form.
      await expect(inviteePage.getByTestId('invite-signup-required')).toBeVisible();
      await submitInviteSignup(inviteePage, generatePassword());

      await expect(inviteePage.getByTestId('invite-signin-required')).toBeVisible();
      await expect(inviteePage.getByTestId('invite-signin-form')).toBeVisible();
      await expect(inviteePage.getByTestId('invite-signin-email-input')).toHaveValue(invitedEmail);

      // Sign in inline with the existing password, then accept
      await inviteePage.getByTestId('invite-signin-password-input').fill(password);
      await inviteePage.getByTestId('invite-signin-submit').click();
      await acceptDirectly(inviteePage);

      await expectMember(owner.page, orgExtid, invitedEmail);
    } finally {
      await Promise.all(opened.map((context) => context.close()));
    }
  });
});

// -----------------------------------------------------------------------------
// INV-005: Existing User with MFA (Skipped - Requires MFA Setup)
// -----------------------------------------------------------------------------

test.describe('INV-005: Existing User MFA Flow', () => {
  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): needs an
  // MFA-enrolled invitee account (TEST_MFA_* — see e2e/support/env.ts).
  // Unimplemented placeholder -> test.fixme. See e2e/QUARANTINE.md.
  test.fixme('existing user with MFA completes invite flow', async () => {
    // TODO(#3421): drive the MFA invite flow with a seeded MFA account.
  });
});

// -----------------------------------------------------------------------------
// INV-006: Signed-in User with Matching Email (Direct Accept)
// -----------------------------------------------------------------------------

test.describe('INV-006: Direct Accept Flow', () => {
  test('signed-in user with matching email can accept directly', async ({ browser }) => {
    const opened: BrowserContext[] = [];

    try {
      // Inviting the storageState owner's own email fails (already a member,
      // see INV-008), so both sides are throwaway accounts: an owner who
      // invites, and a signed-in account whose email matches the invitation.
      const owner = await signUpAndSignIn(browser, opened, 'inv006-owner');
      const invitee = await signUpAndSignIn(browser, opened, 'inv006-invitee');

      const orgExtid = await navigateToOrgTeam(owner.page);
      await createInvitation(owner.page, invitee.email);
      const token = await getInvitationToken(owner.page, invitee.email);
      expect(token).toBeTruthy();

      await invitee.page.goto(`/invite/${token}`);

      // direct_accept: authenticated with the matching email
      await expect(invitee.page.getByTestId('invite-direct-accept')).toBeVisible();
      await expect(invitee.page.getByTestId('accept-invitation-btn')).toBeEnabled();
      await expect(invitee.page.getByTestId('decline-invitation-btn')).toBeVisible();
      await expect(invitee.page.getByTestId('email-mismatch-warning')).toBeHidden();

      await acceptDirectly(invitee.page);

      await expectMember(owner.page, orgExtid, invitee.email);
    } finally {
      await Promise.all(opened.map((context) => context.close()));
    }
  });
});

// -----------------------------------------------------------------------------
// INV-007: Signed-in User with Wrong Email (Continue As Invited Email)
// -----------------------------------------------------------------------------

test.describe('INV-007: Wrong Email State', () => {
  test('signed-in user with wrong email sees continue-as prompt', async ({ browser }) => {
    const ownerContext = await browser.newContext(unauthenticatedContext);
    const wrongUserContext = await browser.newContext(unauthenticatedContext);

    const ownerPage = await ownerContext.newPage();
    const wrongUserPage = await wrongUserContext.newPage();

    try {
      // Owner creates invitation for a DIFFERENT email
      await loginUser(ownerPage);
      const invitedEmail = generateTestEmail('wrong-email-test');
      await navigateToOrgTeam(ownerPage);
      await createInvitation(ownerPage, invitedEmail);
      const token = await getInvitationToken(ownerPage, invitedEmail);
      expect(token).toBeTruthy();

      // Login as test user (different email than invitation)
      await loginUser(wrongUserPage);

      // Visit invitation page
      await wrongUserPage.goto(`/invite/${token}`);
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Should show wrong_email state
      const wrongEmailState = wrongUserPage.getByTestId('invite-wrong-email');
      await expect(wrongEmailState).toBeVisible();

      // Email mismatch warning should be visible
      const mismatchWarning = wrongUserPage.getByTestId('email-mismatch-warning');
      await expect(mismatchWarning).toBeVisible();

      // "Accept with this account" button should NOT be present (strict email binding)
      // The accept button in wrong_email state should not exist or be hidden
      const acceptButton = wrongUserPage.getByTestId('accept-invitation-btn');
      await expect(acceptButton).not.toBeVisible();

      // "Continue as" button should be visible
      const continueAsBtn = wrongUserPage.getByTestId('continue-as-btn');
      await expect(continueAsBtn).toBeVisible();
      await expect(continueAsBtn).toHaveText(/continue as/i);

      // Decline button should also be visible in wrong_email state
      const declineButton = wrongUserPage.getByTestId('decline-invitation-btn');
      await expect(declineButton).toBeVisible();

      // Click continue as — POSTs /auth/logout, then hard-navigates back to
      // the same /invite/:token URL. The URL never changes, so waiting on it
      // proves nothing; wait on the logout response and the reloaded state.
      const logoutResponse = wrongUserPage.waitForResponse(
        (res) =>
          res.request().method() === 'POST' && new URL(res.url()).pathname === '/auth/logout'
      );
      await continueAsBtn.click();
      expect((await logoutResponse).ok()).toBe(true);

      // Back on the invite page (not signin), now rendered for an anonymous
      // visitor: the unauthenticated default is signup_required.
      await expect(wrongUserPage).toHaveURL(new RegExp(`/invite/${token}$`));
      await expect(wrongUserPage.getByTestId('invite-signup-required')).toBeVisible();
      await expect(wrongEmailState).toBeHidden();

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
// INV-008: Already a Member
// -----------------------------------------------------------------------------

test.describe('INV-008: Already Member State', () => {
  test('already member shows info message', async ({ page }) => {
    // The storageState session is the org owner (already a member of their org)
    // Get owner's email
    const bootstrapResponse = await page.request.get('/bootstrap/me');
    const bootstrapData = await bootstrapResponse.json();
    const ownerEmail = bootstrapData.email;
    expect(ownerEmail).toBeTruthy();

    // Navigate to org team and try to create invitation for self
    await navigateToOrgTeam(page);

    // Try to create invitation for owner's own email
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
// INV-009: Expired Invitation
// -----------------------------------------------------------------------------

test.describe('INV-009: Expired Invitation State', () => {
  test('expired invite shows error state', async ({ page }) => {
    // Use a fake token to simulate expired invitation
    const fakeToken = 'expired-fake-token-' + Date.now();

    await page.goto(`/invite/${fakeToken}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show invalid state (expired/revoked/not found)
    const invalidState = page.getByTestId('invite-invalid');
    await expect(invalidState).toBeVisible();

    // Error message should indicate invalid/expired
    await expect(page.getByText(/invalid|expired|not found/i)).toBeVisible();

    // No action buttons should be shown
    const acceptButton = page.getByTestId('accept-invitation-btn');
    const declineButton = page.getByTestId('decline-invitation-btn');

    await expect(acceptButton).not.toBeVisible();
    await expect(declineButton).not.toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// INV-010: Invalid Token (Revoked Invite)
// -----------------------------------------------------------------------------

test.describe('INV-010: Invalid Token State', () => {
  test('invalid token shows error state', async ({ page }) => {
    const invalidToken = 'invalid-token-format-12345-' + Date.now();

    await page.goto(`/invite/${invalidToken}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show invalid state
    const invalidState = page.getByTestId('invite-invalid');
    await expect(invalidState).toBeVisible();

    // Error message should be visible
    await expect(page.getByText(/invalid|expired/i)).toBeVisible();

    // No invitation details should be shown (no organization name, role, etc.)
    const invitationDetails = page.getByTestId('invitation-details');
    await expect(invitationDetails).not.toBeVisible();
  });

  test('revoked invitation link becomes invalid', async ({ page, context }) => {
    // Create an invitation (storageState session is the org owner)
    const testEmail = generateTestEmail('revoke-test');
    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);

    // Get the token
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Find and click revoke button
    const invitationRow = page.getByTestId('org-invitation-row').filter({ hasText: testEmail });
    const revokeButton = invitationRow.getByRole('button', { name: /revoke/i });

    await expect(revokeButton).toBeVisible();
    await revokeButton.click();

    // Wait for revocation to complete
    await expect(page.getByText(/revoked/i)).toBeVisible({ timeout: 10000 });

    // Clear cookies and try to use the revoked invitation
    await context.clearCookies();
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show invalid state
    const invalidState = page.getByTestId('invite-invalid');
    await expect(invalidState).toBeVisible();
  });
});

// -----------------------------------------------------------------------------
// Additional State Tests
// -----------------------------------------------------------------------------

test.describe('Invite Flow State Transitions', () => {
  test('loading state shows spinner during fetch', async ({ page, context }) => {
    // Create invitation first
    const testEmail = generateTestEmail('loading-test');
    await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // Clear cookies
    await context.clearCookies();

    // Hold the invitation fetch open so the loading state is observable,
    // instead of racing a fast response.
    let releaseFetch!: () => void;
    const fetchReleased = new Promise<void>((resolve) => {
      releaseFetch = resolve;
    });
    await page.route(`**/api/invite/${token}`, async (route) => {
      await fetchReleased;
      await route.continue();
    });

    await page.goto(`/invite/${token}`);
    await expect(page.getByTestId('invite-loading')).toBeVisible();
    await expect(page.getByTestId('invite-signup-required')).toBeHidden();

    // Once the fetch completes the loading state gives way to the
    // unauthenticated default
    releaseFetch();
    await expect(page.getByTestId('invite-signup-required')).toBeVisible();
    await expect(page.getByTestId('invite-loading')).toBeHidden();
  });

  test('invitation context displays organization info', async ({ page, context }) => {
    // Create invitation
    const testEmail = generateTestEmail('context-test');
    const orgExtid = await navigateToOrgTeam(page);
    await createInvitation(page, testEmail);
    const token = await getInvitationToken(page, testEmail);
    expect(token).toBeTruthy();

    // The org's display name, read while still signed in as its owner
    const orgResponse = await page.request.get(`/api/organizations/${orgExtid}`);
    expect(orgResponse.ok()).toBe(true);
    const orgName: string = (await orgResponse.json()).record.display_name;
    expect(orgName).toBeTruthy();

    // Clear cookies and visit invitation
    await context.clearCookies();
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Invitation context should show:
    // - Invited email (readonly input prefilled from the invitation; the
    //   email is not rendered as page text in the signup_required state)
    await expect(page.getByTestId('invite-signup-email-input')).toHaveValue(testEmail);

    // - Organization name and role, in the invitation context box
    const invitationContext = page.getByTestId('invitation-context');
    await expect(invitationContext).toBeVisible();
    await expect(invitationContext).toContainText("You've been invited to join");
    await expect(invitationContext).toContainText(orgName);
    await expect(invitationContext).toContainText('Team Member');
  });
});

/**
 * Test Case Reference (INV-001 through INV-010):
 *
 * | ID       | Intent                                                   | Status     |
 * |----------|----------------------------------------------------------|------------|
 * | INV-001  | New user signup + accept atomically                      | Implemented|
 * | INV-002  | New user magic link (feature flag dependent)             | Skipped    |
 * | INV-003  | New user SSO (requires SSO config)                       | Skipped    |
 * | INV-004  | Existing user signin + accept                            | Implemented|
 * | INV-005  | Existing user MFA flow (requires MFA setup)              | Skipped    |
 * | INV-006  | Signed-in user direct accept (matching email)            | Implemented|
 * | INV-007  | Signed-in user wrong email - continue as invited email   | Implemented|
 * | INV-008  | Already a member shows info message                      | Implemented|
 * | INV-009  | Expired invitation shows error state                     | Implemented|
 * | INV-010  | Invalid/revoked token shows error state                  | Implemented|
 */
