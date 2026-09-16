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

async function spendLoginProofWithoutFollowingTheIdp(page: Page): Promise<void> {
  const response = await page.context().request.post(`${origin}/auth/sso/${provider}`, {
    form: { connect: '1' },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(302);
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

    await page.getByTestId(`connections-connect-${provider}`).click();
    await waitForPathname(page, CONNECTIONS_PATH);
    await expect(page.getByTestId('connections-list')).toContainText(uid);
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
    await expect(page.getByText(uid, { exact: true })).toHaveCount(0);
  });
});
