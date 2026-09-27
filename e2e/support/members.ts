// e2e/support/members.ts
//
// Throwaway accounts and organization memberships for the e2e/full/ suites.
//
// The full lane provisions one account (TEST_USER_*, signed up by
// e2e/global.setup.ts) that owns exactly one default workspace and is its
// only member. Tests that need a second member, an admin, or an invitee with
// an existing account build those people here instead: the lane creates
// accounts that can sign in without verifying their email
// (AUTH_VERIFY_ACCOUNT_ENABLED=false) and turns off the per-IP signup limiter
// (CREATE_ACCOUNT_RATE_LIMIT_ENABLED=false), so a test can sign up as many
// throwaway accounts as it needs and join them to an org through the real
// invitation flow, with no mail interceptor.
//
// Every account made here is new, so the shared storageState owner's org
// never gains a member and its account never joins a second org. Suites that
// assert the lane's solo-owner state (scope switcher visibility, member
// counts) stay valid.
//
// Invitations have a budget the signup limiter setting does not lift. Every
// invite page load, signup and accept counts against InviteTokenRateLimiter
// (lib/onetime/security/invite_token_rate_limiter.rb): 100 calls per client
// IP, in a window that restarts on every call, then a 20 minute lockout. It
// has no switch outside RACK_ENV=test. One full/ run makes about 60 such
// calls, and the page then reports "Too many invite requests". Add
// invitation round trips sparingly; share a fixture where tests only read.

import { expect, type Browser, type BrowserContext, type Page } from '@playwright/test';

import { FRESH_CONTEXT, signIn, waitForAppReady } from './auth-journey';
import { getFirstOrganization } from './organizations';

export type InvitableRole = 'member' | 'admin';

export interface Account {
  email: string;
  password: string;
}

/** An account with a live, signed-in page in its own browser context. */
export interface SignedInAccount extends Account {
  context: BrowserContext;
  page: Page;
}

/** A unique address on a domain the app accepts for signup. */
export function uniqueTestEmail(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.onetimesecret.com`;
}

/** A password that satisfies the signup form's requirements. */
export function generatePassword(): string {
  return `Mbr-${Math.random().toString(36).slice(2, 10)}-Pw123!`;
}

/**
 * Open a browser context with no session and record it in `opened`, so the
 * caller's cleanup closes it even when a later step throws.
 *
 * `browser.newContext()` inherits the project's `use` options, including the
 * shared owner's storageState, so it must opt out explicitly.
 */
export async function openFreshContext(
  browser: Browser,
  opened: BrowserContext[]
): Promise<BrowserContext> {
  const context = await browser.newContext(FRESH_CONTEXT);
  opened.push(context);
  return context;
}

/** Close every context in `opened` and empty the list. */
export async function closeContexts(opened: BrowserContext[]): Promise<void> {
  const contexts = opened.splice(0, opened.length);
  await Promise.all(contexts.map((context) => context.close()));
}

/**
 * Register a password account through the signup form. Only valid on a page
 * without a session. Leaves the page on /check-email, signed out.
 */
export async function signUpAccount(page: Page, email: string, password: string): Promise<void> {
  await page.goto('/signup');
  await expect(page.getByTestId('signup-form')).toBeVisible();
  await page.getByTestId('signup-email-input').fill(email);
  await page.getByTestId('signup-password-input').fill(password);
  await page.getByTestId('signup-terms-checkbox').check();
  await page.getByTestId('signup-submit').click();

  await expect(page.getByTestId('check-email-view')).toBeVisible({ timeout: 15_000 });
}

/**
 * Sign in with a password from /signin and wait until the app leaves it.
 * Only valid on a page without a session: a signed-in visitor to /signin is
 * redirected away before the form renders.
 */
export async function signInWithPassword(
  page: Page,
  email: string,
  password: string
): Promise<void> {
  await page.goto('/signin');
  await waitForAppReady(page);
  await signIn(page, email, password);
  await page.waitForURL((url) => !url.pathname.startsWith('/signin'), { timeout: 30_000 });
}

/**
 * Sign up a throwaway account in its own context and sign it in. The account
 * owns its default workspace, so it can invite members.
 */
export async function signUpAndSignIn(
  browser: Browser,
  opened: BrowserContext[],
  prefix: string
): Promise<SignedInAccount> {
  const context = await openFreshContext(browser, opened);
  const page = await context.newPage();
  const email = uniqueTestEmail(prefix);
  const password = generatePassword();

  await signUpAccount(page, email, password);
  await signInWithPassword(page, email, password);

  return { email, password, context, page };
}

/**
 * Open the org's Members tab and wait for its panel. Needs an owner or admin
 * session: /org/:extid requires the admin role on that org.
 */
export async function openMembersTab(page: Page, orgExtid: string): Promise<void> {
  await page.goto(`/org/${orgExtid}/members`);
  await expect(page.getByTestId('org-section-members')).toBeVisible();
}

/**
 * Send an invitation through the Members tab form and wait for the server to
 * accept it. The page must already be on the Members tab.
 *
 * Waits on the POST response, not on the "Invitation sent" alert: the alert
 * from an earlier invitation on the same page is still showing, so it would
 * pass before this request finishes.
 */
export async function inviteMember(
  page: Page,
  email: string,
  role: InvitableRole = 'member'
): Promise<void> {
  await page.getByRole('button', { name: /invite member/i }).click();
  await page.locator('#invite-email').fill(email);
  await page.locator('#invite-role').selectOption(role);

  const created = page.waitForResponse(
    (response) =>
      response.request().method() === 'POST' &&
      /^\/api\/organizations\/[^/]+\/invitations$/.test(new URL(response.url()).pathname)
  );
  await page.getByRole('button', { name: /send invit/i }).click();
  const response = await created;
  expect(response.ok(), `invite ${email}: HTTP ${response.status()}`).toBe(true);

  await expect(page.getByText(/invitation sent/i)).toBeVisible();
}

/**
 * The pending invitation token for `email`, read through the org's
 * invitations API with the inviter's session.
 */
export async function invitationToken(
  page: Page,
  orgExtid: string,
  email: string
): Promise<string> {
  const response = await page.request.get(`/api/organizations/${orgExtid}/invitations`);
  expect(response.ok(), `GET invitations for ${orgExtid}`).toBe(true);
  const data = await response.json();
  const invitation = data.records?.find((inv: { email: string }) => inv.email === email);
  expect(invitation?.token, `a pending invitation for ${email} in ${orgExtid}`).toBeTruthy();
  return invitation.token as string;
}

/**
 * Fill and submit the invite page's inline signup form (signup_required
 * state). The email field is bound to the invited address.
 */
export async function submitInviteSignup(page: Page, password: string): Promise<void> {
  await page.getByTestId('invite-signup-password-input').fill(password);
  await page.getByTestId('invite-signup-confirm-password-input').fill(password);
  await page.getByTestId('invite-signup-terms-checkbox').check();
  await page.getByTestId('invite-signup-submit').click();
}

/**
 * Accept from the invite page's direct_accept state and wait for the join to
 * finish. Afterwards the view pushes to /orgs; a member who owns no org is
 * sent on to /dashboard by the owner-only /orgs guard, so only assert that
 * the invite page is left.
 */
export async function acceptInvitationDirectly(page: Page): Promise<void> {
  await expect(page.getByTestId('invite-direct-accept')).toBeVisible({ timeout: 15_000 });
  await page.getByTestId('accept-invitation-btn').click();
  await expect(page.getByTestId('invite-accepted')).toContainText(
    'Invitation accepted successfully'
  );
  await expect(page).not.toHaveURL(/\/invite\//, { timeout: 10_000 });
}

/** Assert through the members API that `email` is a member with `role`. */
export async function expectMember(
  page: Page,
  orgExtid: string,
  email: string,
  role: InvitableRole | 'owner' = 'member'
): Promise<void> {
  const response = await page.request.get(`/api/organizations/${orgExtid}/members`);
  expect(response.ok(), `GET members for ${orgExtid}`).toBe(true);
  const data = await response.json();
  const member = data.records?.find((m: { email: string }) => m.email === email);
  expect(member, `${email} is a member of ${orgExtid}`).toBeTruthy();
  expect(member.role, `${email}'s role in ${orgExtid}`).toBe(role);
}

/**
 * Join a brand-new account to the owner's org with `role`: the owner invites
 * a fresh address, the invitee signs up inline on the invite page (in its own
 * context) and accepts. Returns the invitee, signed in. The owner's page must
 * be on the org's Members tab.
 */
export async function addMember(
  browser: Browser,
  opened: BrowserContext[],
  ownerPage: Page,
  orgExtid: string,
  role: InvitableRole,
  prefix: string
): Promise<SignedInAccount> {
  const email = uniqueTestEmail(prefix);
  const password = generatePassword();

  await inviteMember(ownerPage, email, role);
  const token = await invitationToken(ownerPage, orgExtid, email);

  const context = await openFreshContext(browser, opened);
  const page = await context.newPage();
  await page.goto(`/invite/${token}`);
  await expect(page.getByTestId('invite-signup-required')).toBeVisible();
  await expect(page.getByTestId('invite-signup-email-input')).toHaveValue(email);
  await submitInviteSignup(page, password);
  await acceptInvitationDirectly(page);

  await expectMember(ownerPage, orgExtid, email, role);
  return { email, password, context, page };
}

/**
 * A throwaway owner signed in on its own default workspace, with the Members
 * tab open. Starting point for tests that add members.
 */
export async function createOwnerWithOrg(
  browser: Browser,
  opened: BrowserContext[],
  prefix: string
): Promise<{ owner: SignedInAccount; orgExtid: string }> {
  const owner = await signUpAndSignIn(browser, opened, prefix);
  const { extid } = await getFirstOrganization(owner.page);
  await openMembersTab(owner.page, extid);
  return { owner, orgExtid: extid };
}

/**
 * JSON + CSRF headers for a state-changing API call made with the page's
 * session. The CSRF token (shrimp) comes from /bootstrap/me.
 */
export async function apiHeaders(page: Page): Promise<Record<string, string>> {
  const response = await page.request.get('/bootstrap/me');
  expect(response.ok(), 'GET /bootstrap/me').toBe(true);
  const { shrimp } = (await response.json()) as { shrimp?: string };
  expect(shrimp, '/bootstrap/me carries a CSRF token').toBeTruthy();
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-CSRF-Token': shrimp as string,
  };
}
