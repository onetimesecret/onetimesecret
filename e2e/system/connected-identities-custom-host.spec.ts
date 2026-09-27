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
const initiationPath = `/auth/sso/${provider}`;

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

// Where the initiation's 302 must point, decided before OmniAuth runs by the
// connect-intent step (apps/web/auth/config/hooks/omniauth.rb): a stale or
// spent login proof goes to /reauth carrying the panel path as `redirect`
// (connect_reauth_redirect); a fresh proof goes on to the IdP, which under
// OmniAuth test mode (tenant_connect_test_boot.rb) is the provider's own
// callback path. Read off the Location header itself so a wrong destination
// fails here, not later when the page happens to land somewhere else.
type InitiationOutcome = 'reauth' | 'idp';

function expectInitiationLocation(location: string | undefined, outcome: InitiationOutcome): void {
  expect(location, 'initiation 302 must carry a Location header').toBeTruthy();
  const target = new URL(location ?? '', origin);
  if (outcome === 'reauth') {
    expect(target.pathname, 'spent login proof must redirect to re-authentication').toBe('/reauth');
    expect(target.searchParams.get('redirect'), 're-authentication must return to the panel').toBe(
      CONNECTIONS_PATH
    );
  } else {
    expect(target.pathname, 'fresh login proof must redirect on to the IdP').toBe(
      `${initiationPath}/callback`
    );
  }
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
  expectInitiationLocation(response.headers()['location'], 'idp');
}

async function openConnections(page: Page): Promise<void> {
  await page.goto(`${origin}${CONNECTIONS_PATH}`);
  await waitForAppReady(page);
  await expect(page.getByTestId('connections-connect')).toBeVisible();
}

// The Connect button submits a native POST form (submitSsoLogin), a
// document navigation, not a fetch(). What Origin the browser puts on that
// navigation is decided by the document's referrer policy: under
// `no-referrer` it is the literal `null`, which HttpOrigin refuses with 403
// before OmniAuth runs (#4542). The document policy is `strict-origin`, so
// the exact tenant origin, port included, must arrive, and the initiation
// must be answered with a redirect (to /reauth or to the IdP), never 403.
// The Referer, when the browser sends one, may be the origin and nothing
// more: no path, no query.
async function clickConnectAsNativeForm(page: Page, outcome: InitiationOutcome): Promise<void> {
  const [request] = await Promise.all([
    page.waitForRequest(
      (candidate) =>
        candidate.method() === 'POST' &&
        new URL(candidate.url()).pathname === initiationPath &&
        candidate.isNavigationRequest()
    ),
    page.getByTestId(`connections-connect-${provider}`).click(),
  ]);

  const headers = await request.allHeaders();
  expect(headers['origin'], 'native SSO initiation must carry the tenant origin').toBe(origin);
  expect(headers['referer'] ?? `${origin}/`, 'Referer on the initiation must be origin-only').toBe(
    `${origin}/`
  );

  const response = await request.response();
  expect(response?.status(), 'initiation must be redirected, not refused by HttpOrigin (403)').toBe(
    302
  );
  expectInitiationLocation((await response?.allHeaders())?.['location'], outcome);
}

async function reauthenticateFromPanel(page: Page): Promise<void> {
  await clickConnectAsNativeForm(page, 'reauth');
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
    await clickConnectAsNativeForm(page, 'idp');
    await waitForPathname(page, CONNECTIONS_PATH);
    await waitForAppReady(page);
    await expect(page.getByTestId('connections-list')).toContainText(maskedUid);
    // Tenant surface: the panel never suppresses Connect on route-name
    // evidence (sso-link-evidence.ts), so the button stays offered next to the
    // bound identity. The platform surface would hide it here.
    await expect(page.getByTestId(`connections-connect-${provider}`)).toBeVisible();
  });

  test('the same tuple refuses for another tenant member without changing their session', async ({
    page,
  }) => {
    await loginOnTenant(page, secondEmail);
    await spendLoginProofWithoutFollowingTheIdp(page);
    await openConnections(page);
    await reauthenticateFromPanel(page);

    await clickConnectAsNativeForm(page, 'idp');
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
