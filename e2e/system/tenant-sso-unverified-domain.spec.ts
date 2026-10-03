import { expect, test } from '@playwright/test';

import { waitForAppReady } from '../support/auth-journey';

// Companion to connected-identities-custom-host.spec.ts, run by the same
// `tenant-connect` project against the same armed test process. That journey
// proves tenant SSO works on a VERIFIED custom domain; this check proves the
// same tenant shape is refused while the domain's ownership is unverified
// (#4579). tenant_connect_seed.rb seeds the second host identical to the
// first except for `verified`, and with no accounts: the refusal happens
// before anyone signs in, so there is no state to share with the journey.

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

const unverifiedOrigin = new URL(required('E2E_TENANT_CONNECT_UNVERIFIED_ORIGIN')).origin;
const provider = process.env.E2E_TENANT_CONNECT_PROVIDER?.trim() || 'oidc';
const initiationPath = `/auth/sso/${provider}`;
const callbackPath = `${initiationPath}/callback`;
const REFUSAL_CODE = 'sso_domain_unverified';
// `web.login.errors.sso_domain_unverified` (en), asserted as a substring the
// same way sso-missing-email.spec.ts pins its copy. Login.vue maps unknown
// auth_error codes to the generic sso_failed copy, so a visible banner alone
// would not prove this code is mapped.
const REFUSAL_TEXT = 'is not active yet because the domain has not finished verification';

test.describe('tenant SSO on an unverified custom domain', () => {
  test('starting SSO is refused with sso_domain_unverified and never reaches the IdP', async ({
    page,
  }) => {
    // Under OmniAuth test mode the request phase stands in for the IdP: it
    // answers the initiation with a redirect straight to the callback. So
    // "never reaches the IdP" is: no request to the callback path, on ANY host
    // (an unverified domain's callback URL builds on the canonical host).
    const callbackRequests: string[] = [];
    page.on('request', (request) => {
      if (new URL(request.url()).pathname === callbackPath) callbackRequests.push(request.url());
    });

    await page.goto(`${unverifiedOrigin}/signin`);
    await waitForAppReady(page);

    // Display half of the same availability ladder the runtime refusal below
    // reads: the page offers no SSO button, neither the tenant's provider nor
    // a platform fallback.
    await expect(page.getByTestId('sso-button')).toHaveCount(0);

    // With no button to click, start SSO the way SsoButton does
    // (submitSsoLogin: a top-level form POST of shrimp / redirect / connect).
    // The form lives outside the app's mount point, so Vue never re-renders
    // it away, and is pinned above the page so no overlay intercepts the
    // click. A real click submits it: form.submit() inside page.evaluate
    // would race the navigation it starts against the evaluate's own result.
    await page.evaluate((action) => {
      const form = document.createElement('form');
      form.method = 'POST';
      form.action = action;
      form.dataset.testid = 'unverified-sso-initiation';
      form.style.cssText = 'position:fixed;top:0;left:0;z-index:2147483647';
      for (const name of ['shrimp', 'redirect', 'connect']) {
        const field = document.createElement('input');
        field.type = 'hidden';
        field.name = name;
        field.value = '';
        form.appendChild(field);
      }
      const submit = document.createElement('button');
      submit.type = 'submit';
      submit.textContent = 'Start SSO';
      form.appendChild(submit);
      document.body.appendChild(form);
    }, initiationPath);

    // Both waits are armed before the click: Login.vue strips auth_error from
    // the address bar once it has read it, so a wait started late could miss
    // the landing URL.
    const [initiation] = await Promise.all([
      page.waitForResponse(
        (candidate) =>
          candidate.request().method() === 'POST' &&
          new URL(candidate.url()).pathname === initiationPath
      ),
      page.waitForURL(
        (url) => url.pathname === '/signin' && url.searchParams.get('auth_error') === REFUSAL_CODE
      ),
      page.getByTestId('unverified-sso-initiation').getByRole('button').click(),
    ]);

    // The initiation itself is refused: its own response redirects to the
    // sign-in page, not onward to the (mock) IdP, and not through platform
    // credentials.
    expect(initiation.status()).toBe(302);
    const location = new URL(initiation.headers()['location'] ?? '', unverifiedOrigin);
    expect(location.pathname).toBe('/signin');
    expect(location.searchParams.get('auth_error')).toBe(REFUSAL_CODE);

    // The visitor stays on the tenant's host and sees the pending-verification
    // error, not a blank page and not the generic SSO failure.
    expect(new URL(page.url()).origin).toBe(unverifiedOrigin);
    await waitForAppReady(page);
    const banner = page.getByTestId('signin-auth-error');
    await expect(banner).toBeVisible();
    await expect(banner).toContainText(REFUSAL_TEXT);

    expect(callbackRequests).toEqual([]);
  });
});
