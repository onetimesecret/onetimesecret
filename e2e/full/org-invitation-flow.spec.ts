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
 * - Full auth mode with accounts that can sign in without verifying their
 *   email (the full lane sets AUTH_VERIFY_ACCOUNT_ENABLED=false): the journeys
 *   that accept an invitation (INV-005, INV-017) sign up throwaway accounts
 *   (e2e/support/members.ts), so the storageState owner's org never gains a
 *   member. No mail interceptor is needed: tests read invitation tokens
 *   through the owner's invitations API.
 * - Application running locally or PLAYWRIGHT_BASE_URL set
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

import { type BrowserContext, expect, test } from '@playwright/test';

import {
  acceptInvitationDirectly,
  addMember,
  closeContexts,
  createOwnerWithOrg,
  expectMember,
  invitationToken,
  inviteMember,
  openFirstOrgMembersTab,
  openFreshContext,
  signInAsTestUser,
  signUpAndSignIn,
  uniqueTestEmail,
} from '../support/members';

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
    const testEmail = uniqueTestEmail('invitee');

    // Navigate to org team settings
    await openFirstOrgMembersTab(page);

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
  test('Unauthenticated user sees the inline signup form on the invitation page', async ({
    page,
    context,
  }) => {
    // First, create an invitation as org owner
    const testEmail = uniqueTestEmail('inline-auth-test');
    const orgExtid = await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);

    // Get the invitation token
    const token = await invitationToken(page, orgExtid, testEmail);

    // Clear cookies to simulate unauthenticated user
    await context.clearCookies();

    // Visit invitation link
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // An unauthenticated visitor always starts in signup_required: the
    // invite API never says whether the invited email has an account
    // (AZ7/#3856). signin_required only follows a signup attempt for an
    // address that already has one.
    await expect(page.getByTestId('invite-signup-required')).toBeVisible();
    await expect(page.getByTestId('invite-signin-required')).toBeHidden();
    await expect(page.getByTestId('invite-signup-form')).toBeVisible();
    // The invited email is bound into the form (readonly input value)
    await expect(page.getByTestId('invite-signup-email-input')).toHaveValue(testEmail);

    // The form's "Continue" submit is the accept path; Decline sits beside
    // it. There is no standalone Accept button in this state.
    await expect(page.getByTestId('invite-signup-submit')).toBeVisible();
    await expect(page.getByTestId('invite-signup-decline')).toBeVisible();
    await expect(page.getByTestId('accept-invitation-btn')).toBeHidden();
  });
});

test.describe('INV-003: Email Mismatch Warning', () => {
  test('User logged in with different email sees clear mismatch warning with continue-as option', async ({
    browser,
  }) => {
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('mismatch-invited');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Different user logs in and visits invitation
      await signInAsTestUser(wrongUserPage); // The test user, not the invited email

      await wrongUserPage.goto(`/invite/${token}`);
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Verify wrong_email state is shown
      const wrongEmailState = wrongUserPage.getByTestId('invite-wrong-email');
      await expect(wrongEmailState).toBeVisible();

      // Verify email mismatch warning is visible (using testid)
      const mismatchWarning = wrongUserPage.getByTestId('email-mismatch-warning');
      await expect(mismatchWarning).toBeVisible();

      // Verify warning shows factual "Different account" framing. The
      // copy + the "Continue as" button both match, so scope to the first
      // to avoid a strict-mode violation.
      await expect(wrongUserPage.getByText(/different|mismatch/i).first()).toBeVisible();

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
      await closeContexts(opened);
    }
  });
});

test.describe('INV-004: Continue As Invited Email Flow', () => {
  test('Clicking Continue As logs out and redirects to invite page', async ({ browser }) => {
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Owner creates invitation
      await signInAsTestUser(ownerPage);
      const invitedEmail = uniqueTestEmail('switch-account');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, invitedEmail);
      const token = await invitationToken(ownerPage, orgExtid, invitedEmail);

      // Wrong user logs in and visits invitation
      await signInAsTestUser(wrongUserPage);
      await wrongUserPage.goto(`/invite/${token}`);
      await expect(wrongUserPage.locator('html[data-app-ready="true"]')).toBeAttached();

      // Click continue as — logs out and redirects to invite page
      const continueAsBtn = wrongUserPage.getByRole('button', { name: /continue as/i });
      await continueAsBtn.click();

      // Verify redirected back to invite page (not signin)
      await wrongUserPage.waitForURL(/\/invite\//, { timeout: 10000 });

      // Verify the user is logged out. "Continue as" clears the session and
      // redirects; the cookie clear can lag the URL change by a beat (the
      // redirect target already matches /invite/), so poll /bootstrap/me until
      // the session is actually gone instead of sampling once — sampling once
      // is the race that made this test pass only on retry.
      await expect
        .poll(
          async () => {
            const response = await wrongUserPage.request.get('/bootstrap/me');
            const data = await response.json();
            return Boolean(data.authenticated);
          },
          { timeout: 10000 }
        )
        .toBe(false);
    } finally {
      await closeContexts(opened);
    }
  });
});

test.describe('INV-005: Matching Email User Flow', () => {
  test('User logged in with matching email can immediately accept invitation', async ({
    browser,
  }) => {
    const opened: BrowserContext[] = [];
    try {
      // Both sides are throwaway accounts: the invitee must already be
      // signed in with the invited address, and accepting joins it to the
      // inviter's org, which must not be the storageState owner's.
      const { owner, orgExtid } = await createOwnerWithOrg(browser, opened, 'inv005-owner');
      const invitee = await signUpAndSignIn(browser, opened, 'inv005-invitee');
      await inviteMember(owner.page, invitee.email);
      const token = await invitationToken(owner.page, orgExtid, invitee.email);

      await invitee.page.goto(`/invite/${token}`);

      // Signed in with the invited address: straight to direct_accept, with
      // no signup or signin form in the way.
      await expect(invitee.page.getByTestId('invite-direct-accept')).toBeVisible();
      await expect(invitee.page.getByTestId('invite-signup-form')).toBeHidden();
      await expect(invitee.page.getByTestId('invite-signin-form')).toBeHidden();
      await expect(invitee.page.getByTestId('email-mismatch-warning')).toBeHidden();

      await acceptInvitationDirectly(invitee.page);
      await expectMember(owner.page, orgExtid, invitee.email);
    } finally {
      await closeContexts(opened);
    }
  });
});

// -----------------------------------------------------------------------------
// SECTION 3: Decline and Error States
// -----------------------------------------------------------------------------

test.describe('INV-007a: Authenticated Decline Flow', () => {
  test('Authenticated user can decline invitation and is redirected home', async ({ page }) => {
    // Create invitation
    const testEmail = uniqueTestEmail('decline-auth');
    const orgExtid = await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);
    const token = await invitationToken(page, orgExtid, testEmail);

    // Visit invitation page (still logged in as owner - simulates matching email)
    await page.goto(`/invite/${token}`);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Click decline (use testid to avoid matching "Continue as decline-..." button)
    const declineButton = page.getByTestId('decline-invitation-btn');
    await declineButton.click();

    // Verify success message
    await expect(page.getByText(/declined/i)).toBeVisible({ timeout: 10000 });

    // Verify redirected to home after delay (use toHaveURL to check current state)
    await expect(page).toHaveURL(/^\/$|\/dashboard/, { timeout: 5000 });
  });
});

test.describe('INV-007b: Unauthenticated Decline Flow', () => {
  test('Unauthenticated user can decline invitation without signing in', async ({
    page,
    browser,
  }) => {
    const opened: BrowserContext[] = [];
    try {
      // The storageState owner invites; the invitee declines, so the owner's
      // org gains no member.
      const extid = await openFirstOrgMembersTab(page);
      const testEmail = uniqueTestEmail('decline-unauth');
      await inviteMember(page, testEmail);
      const token = await invitationToken(page, extid, testEmail);

      // The invitee opens the link with no session. The unauthenticated
      // default state, signup_required, carries its own decline control
      // (invite-signup-decline), not the signed-in decline-invitation-btn.
      const visitor = await (await openFreshContext(browser, opened)).newPage();
      await visitor.goto(`/invite/${token}`);
      await expect(visitor.getByTestId('invite-signup-required')).toBeVisible();
      await visitor.getByTestId('invite-signup-decline').click();

      await expect(visitor.getByTestId('invite-declined')).toBeVisible();
      // After the confirmation the page sends the visitor home. Signed out,
      // home is the bare origin: nothing redirects "/" to /dashboard.
      await expect(visitor).toHaveURL((url) => url.pathname === '/', { timeout: 10_000 });

      // The server recorded the decline: the invitation is no longer pending.
      const response = await page.request.get(`/api/organizations/${extid}/invitations`);
      expect(response.ok(), `GET invitations for ${extid}`).toBe(true);
      const data = await response.json();
      const pending = data.records?.find((inv: { email: string }) => inv.email === testEmail);
      expect(pending, `${testEmail} is no longer pending`).toBeUndefined();
    } finally {
      await closeContexts(opened);
    }
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
    const testEmail = uniqueTestEmail('resend');

    await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);

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
    const testEmail = uniqueTestEmail('revoke');

    const orgExtid = await openFirstOrgMembersTab(page);
    await inviteMember(page, testEmail);

    // Get token before revoking
    const token = await invitationToken(page, orgExtid, testEmail);

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
    await openFirstOrgMembersTab(page);

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
  test('Open redirect attack prevention validates redirect parameter', async ({ context }) => {
    const maliciousRedirects = [
      'https://evil.com/phishing',
      '//evil.com/path',
      'javascript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
    ];

    for (const maliciousUrl of maliciousRedirects) {
      // This exercises the *login form's* redirect handling, so every attempt
      // starts signed out (an authenticated visitor to /signin is redirected
      // away before the form renders) and on its own page, so navigations the
      // previous sign-in started cannot abort this one.
      await context.clearCookies();
      const page = await context.newPage();
      await page.goto(`/signin?redirect=${encodeURIComponent(maliciousUrl)}`);
      const appOrigin = new URL(page.url()).origin;

      // Use the form's test ids — getByLabel(/password/i) also matches the
      // show-password toggle and the "Forgot your password?" link.
      const emailInput = page.getByTestId('signin-email-input');
      await expect(emailInput, `signin form for redirect=${maliciousUrl}`).toBeVisible();
      await emailInput.fill(process.env.TEST_USER_EMAIL || '');
      await page.getByTestId('signin-password-input').fill(process.env.TEST_USER_PASSWORD || '');
      await page.getByTestId('signin-submit').click();

      // Signing in leaves /signin, and must land on this app, not the target
      await page.waitForURL((url) => url.pathname !== '/signin');
      expect(new URL(page.url()).origin, `redirect=${maliciousUrl}`).toBe(appOrigin);
      await page.close();
    }
  });
});

test.describe('INV-SEC-002: Account Enumeration Prevention', () => {
  test('Continue-as flow does not reveal whether invited email has existing account', async ({
    browser,
  }) => {
    const opened: BrowserContext[] = [];

    try {
      const ownerPage = await (await openFreshContext(browser, opened)).newPage();
      const wrongUserPage = await (await openFreshContext(browser, opened)).newPage();

      // Create invitation for an email that doesn't exist
      await signInAsTestUser(ownerPage);
      const nonExistentEmail = uniqueTestEmail('nonexistent');
      const orgExtid = await openFirstOrgMembersTab(ownerPage);
      await inviteMember(ownerPage, nonExistentEmail);
      const token = await invitationToken(ownerPage, orgExtid, nonExistentEmail);

      // Log in as different user and visit invitation
      await signInAsTestUser(wrongUserPage);
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
      await closeContexts(opened);
    }
  });
});

// -----------------------------------------------------------------------------
// Full Integration Flow
// -----------------------------------------------------------------------------

test.describe('INV-017: Complete Invitation Acceptance Flow', () => {
  test('After accepting invitation, user can see and access the organization in their org list', async ({
    browser,
  }) => {
    const opened: BrowserContext[] = [];
    try {
      // A throwaway owner invites a new address; the invitee signs up on the
      // invite page and accepts (addMember), so no storageState account is
      // touched.
      const { owner, orgExtid } = await createOwnerWithOrg(browser, opened, 'inv017-owner');
      const member = await addMember(browser, opened, owner.page, orgExtid, 'member', 'inv017');

      // The member's own organization list names the org, with its role.
      // (The /orgs page is owner-only, so the list is read from the API it
      // and the workspace switcher use.)
      const list = await member.page.request.get('/api/organizations');
      expect(list.ok(), "GET the member's organizations").toBe(true);
      const { records } = (await list.json()) as {
        records?: { extid: string; current_user_role?: string }[];
      };
      const joined = records?.find((org) => org.extid === orgExtid);
      expect(joined, `${orgExtid} in the member's organizations`).toBeTruthy();
      expect(joined?.current_user_role).toBe('member');

      // And the member can open it: the org read requires membership.
      const detail = await member.page.request.get(`/api/organizations/${orgExtid}`);
      expect(detail.ok(), `GET ${orgExtid} as its member`).toBe(true);
    } finally {
      await closeContexts(opened);
    }
  });
});

/**
 * Test Case Reference (from org-invitation-flow.yaml):
 *
 * | ID           | Intent                                                    | Priority   |
 * |--------------|-----------------------------------------------------------|------------|
 * | INV-001      | Owner sends invitation with validation                    | Critical   |
 * | INV-002      | Unauthenticated visitor gets the inline signup form       | Critical   |
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
