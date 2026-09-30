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

import { type BrowserContext, expect, test } from '@playwright/test';

import {
  acceptInvitationDirectly,
  closeContexts,
  expectMember,
  generatePassword,
  invitationToken,
  inviteMember,
  openFirstOrgMembersTab,
  openFreshContext,
  signInAsTestUser,
  signUpAccount,
  signUpAndSignIn,
  submitInviteSignup,
  uniqueTestEmail,
} from '../support/members';

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
      const orgExtid = await openFirstOrgMembersTab(owner.page);
      const invitedEmail = uniqueTestEmail('new-user-signup');
      await inviteMember(owner.page, invitedEmail);
      const token = await invitationToken(owner.page, orgExtid, invitedEmail);

      // New user (no account, not signed in) opens the invitation
      const page = await (await openFreshContext(browser, opened)).newPage();
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
      await acceptInvitationDirectly(page);

      // The owner now sees the new user in the org
      await expectMember(owner.page, orgExtid, invitedEmail);
    } finally {
      await closeContexts(opened);
    }
  });
});

// -----------------------------------------------------------------------------
// INV-002: New User Magic Link (Skipped - Requires Feature Flag)
// -----------------------------------------------------------------------------

test.describe('INV-002: New User Magic Link Flow', () => {
  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): magic
  // links are off unless AUTH_EMAIL_AUTH_ENABLED=true, the link arrives by
  // email (so a mail interceptor must catch it), and the invite page offers
  // one only on a custom domain or on a host restricted to email auth
  // (show_invite.rb, AcceptInvite.vue). The full lane has none of these.
  // Unimplemented placeholder -> test.fixme. See e2e/QUARANTINE.md.
  test.fixme('new user can join via magic link', async () => {
    // TODO(#3421): drive the magic-link join once a lane provides all three.
  });
});

// -----------------------------------------------------------------------------
// INV-003: New User SSO (Skipped - Requires SSO Configuration)
// -----------------------------------------------------------------------------

test.describe('INV-003: New User SSO Flow', () => {
  // QUARANTINED (E2E remediation plan Phase 2.4 / PR 5, issue #3421): needs
  // an SSO identity provider, and the invite page offers SSO only on a custom
  // domain with SSO available or on a host restricted to SSO
  // (show_invite.rb, AcceptInvite.vue). Unimplemented placeholder ->
  // test.fixme. See e2e/QUARANTINE.md.
  test.fixme('new user can join via SSO', async () => {
    // TODO(#3421): drive the SSO join once a lane provides an IdP. The token
    // comes from the invitations API, as in INV-001.
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
      const orgExtid = await openFirstOrgMembersTab(owner.page);

      // The invited email already has an account; its owner is signed out
      const inviteePage = await (await openFreshContext(browser, opened)).newPage();
      const invitedEmail = uniqueTestEmail('existing-user');
      const password = generatePassword();
      await signUpAccount(inviteePage, invitedEmail, password);

      await inviteMember(owner.page, invitedEmail);
      const token = await invitationToken(owner.page, orgExtid, invitedEmail);

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
      await acceptInvitationDirectly(inviteePage);

      await expectMember(owner.page, orgExtid, invitedEmail);
    } finally {
      await closeContexts(opened);
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

      const orgExtid = await openFirstOrgMembersTab(owner.page);
      await inviteMember(owner.page, invitee.email);
      const token = await invitationToken(owner.page, orgExtid, invitee.email);

      await invitee.page.goto(`/invite/${token}`);

      // direct_accept: authenticated with the matching email
      await expect(invitee.page.getByTestId('invite-direct-accept')).toBeVisible();
      await expect(invitee.page.getByTestId('accept-invitation-btn')).toBeEnabled();
      await expect(invitee.page.getByTestId('decline-invitation-btn')).toBeVisible();
      await expect(invitee.page.getByTestId('email-mismatch-warning')).toBeHidden();

      await acceptInvitationDirectly(invitee.page);

      await expectMember(owner.page, orgExtid, invitee.email);
    } finally {
      await closeContexts(opened);
    }
  });
});

// -----------------------------------------------------------------------------
// INV-007: Signed-in User with Wrong Email (Continue As Invited Email)
// -----------------------------------------------------------------------------

test.describe('INV-007: Wrong Email State', () => {
  test('signed-in user with wrong email sees continue-as prompt', async ({ browser }) => {
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation for a DIFFERENT email
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('wrong-email-test');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Login as test user (different email than invitation)
      await signInAsTestUser(wrongUserPage);

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
      await closeContexts(opened);
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
    await openFirstOrgMembersTab(page);

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
    const testEmail = uniqueTestEmail('revoke-test');
    const orgExtid = await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);

    // Get the token
    const token = await invitationToken(page, orgExtid, testEmail);

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
    const testEmail = uniqueTestEmail('loading-test');
    const orgExtid = await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);
    const token = await invitationToken(page, orgExtid, testEmail);

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
    const testEmail = uniqueTestEmail('context-test');
    const orgExtid = await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);
    const token = await invitationToken(page, orgExtid, testEmail);

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
