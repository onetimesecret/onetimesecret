import { expect, test, type Page } from '@playwright/test';

import { signIn, waitForAppReady, waitForPathname } from '../support/auth-journey';

const CONNECTIONS_PATH = '/account/settings/security/connections';

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(
      `${name} is required by the tenant-connect Playwright project. ` +
        'Run it only against the explicitly armed tenant Connect test process.'
    );
  }
  return value;
}

const origin = required('E2E_TENANT_CONNECT_ORIGIN');
const provider = process.env.E2E_TENANT_CONNECT_PROVIDER?.trim() || 'oidc';
const uid = required('E2E_TENANT_CONNECT_UID');
const password = required('E2E_TENANT_CONNECT_PASSWORD');
const ownerEmail = required('E2E_TENANT_CONNECT_OWNER_EMAIL');
const secondEmail = required('E2E_TENANT_CONNECT_SECOND_EMAIL');

// GET /auth/identities never echoes the full IdP subject: the route masks it
// to first4 + U+2026 + last4 (apps/web/auth/routes/identities.rb mask_uid),
// and fully masks anything of 8 characters or fewer. The panel renders that
// masked form, so that is what a bound identity looks like on screen.
if (uid.length <= 8) {
  throw new Error(
    'E2E_TENANT_CONNECT_UID must be longer than 8 characters so the bound identity is distinguishable on the panel.'
  );
}
const maskedUid = `${uid.slice(0, 4)}\u2026${uid.slice(-4)}`;

async function loginOnTenant(page: Page, email: string): Promise<void> {
  await page.goto(`${origin}/signin`);
  await waitForAppReady(page);
  await signIn(page, email, password);
  await page.waitForURL((url) => url.pathname !== '/signin');

  const cookies = await page.context().cookies(origin);
  const session = cookies.find((cookie) => cookie.name === 'onetime.session');
  expect(session, 'custom-host login must establish a session cookie').toBeDefined();
  expect(session?.domain).toBe(new URL(origin).hostname);
}

// Issued from INSIDE the page, not through page.context().request: the
// synthetic tenant host resolves only through Chromium's --host-resolver-rules
// (tenantConnectLaunchOptions), which Playwright's Node-side request context
// does not consult — it getaddrinfo()s the real name and fails with ENOTFOUND.
// `redirect: 'manual'` leaves the 302 unfollowed so the minted intent is never
// consumed by the callback; Playwright still observes the 302 and its Location
// on the network event, which is the evidence that the login proof was accepted
// (a refused initiation redirects to /reauth instead).
async function spendLoginProofWithoutFollowingTheIdp(page: Page): Promise<void> {
  const initiationPath = `/auth/sso/${provider}`;
  const [response] = await Promise.all([
    page.waitForResponse(
      (candidate) =>
        candidate.request().method() === 'POST' &&
        new URL(candidate.url()).pathname === initiationPath
    ),
    page.evaluate(async (path) => {
      await fetch(path, {
        method: 'POST',
        body: new URLSearchParams({ connect: '1' }),
        redirect: 'manual',
        credentials: 'same-origin',
      });
    }, initiationPath),
  ]);
  expect(response.status()).toBe(302);
  const location = response.headers()['location'] ?? '';
  expect(new URL(location, origin).pathname).toBe(`${initiationPath}/callback`);
}

async function openConnections(page: Page): Promise<void> {
  await page.goto(`${origin}${CONNECTIONS_PATH}`);
  await waitForAppReady(page);
  await expect(page.getByTestId('connections-connect')).toBeVisible();
}

async function reauthenticateFromPanel(page: Page): Promise<void> {
  await page.getByTestId(`connections-connect-${provider}`).click();
  await waitForPathname(page, '/reauth');
  await expect(page.getByTestId('reauth-password-form')).toBeVisible();
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Continue' }).click();
  await waitForPathname(page, CONNECTIONS_PATH);
}

test.describe.serial('custom-host Connected Identities journey', () => {
  test('panel → local re-authentication → Connect callback binds the tenant identity', async ({
    page,
  }) => {
    await loginOnTenant(page, ownerEmail);

    // A password login itself records a recent proof. Spend it without following
    // the IdP redirect so the visible journey must use the /reauth screen.
    await spendLoginProofWithoutFollowingTheIdp(page);
    await openConnections(page);
    await reauthenticateFromPanel(page);

    // A completed Connect returns to the panel by itself: the callback honours
    // the `redirect` field submitSsoLogin posts (a refusal goes to
    // /signin?auth_error=… instead).
    await page.getByTestId(`connections-connect-${provider}`).click();
    await waitForPathname(page, CONNECTIONS_PATH);
    await waitForAppReady(page);
    await expect(page.getByTestId('connections-list')).toContainText(maskedUid);
    await expect(page.getByTestId(`connections-connect-${provider}`)).toHaveCount(0);
  });

  test('the same tuple refuses for another tenant member without changing their session', async ({
    page,
  }) => {
    await loginOnTenant(page, secondEmail);
    await spendLoginProofWithoutFollowingTheIdp(page);
    await openConnections(page);
    await reauthenticateFromPanel(page);

    await page.getByTestId(`connections-connect-${provider}`).click();
    await page.waitForURL(
      (url) =>
        url.pathname === '/signin' &&
        url.searchParams.get('auth_error') === 'identity_connect_conflict'
    );

    await page.goto(`${origin}${CONNECTIONS_PATH}`);
    await waitForAppReady(page);
    await expect(page.getByTestId(`connections-connect-${provider}`)).toBeVisible();
    await expect(page.getByTestId('connections-empty')).toBeVisible();
    await expect(page.getByTestId('connections-list')).toHaveCount(0);
    await expect(page.getByText(maskedUid)).toHaveCount(0);
  });
});
