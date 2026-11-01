import { expect, test } from '@playwright/test';

// Companion to connected-identities-custom-host.spec.ts, run by the same
// `tenant-connect` project against the same armed test process. That journey
// proves tenant SSO works on a VERIFIED custom domain; this check proves the
// same tenant shape is not served at all while the domain's ownership is
// unverified. tenant_connect_seed.rb seeds the second host identical to the
// first except for `verified`, and with no accounts.
//
// The lane runs DOMAINS_VALIDATION_STRATEGY=caddy_on_demand, a strategy that
// checks ownership, so DomainStrategy answers every request to the unverified
// host with the same 404 before the web or auth app runs
// (CustomDomain#served_as_tenant?).

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
// DomainStrategy#unverified_domain_response: one fixed body for every such
// host and path.
const NOT_CONFIGURED = 'This domain is not configured';

test.describe('tenant SSO on an unverified custom domain', () => {
  test('the host answers 404 and starting SSO never reaches the IdP', async ({ page }) => {
    // Under OmniAuth test mode the request phase stands in for the IdP: it
    // answers the initiation with a redirect straight to the callback. So
    // "never reaches the IdP" is: no request to the callback path, on ANY host.
    const callbackRequests: string[] = [];
    page.on('request', (request) => {
      if (new URL(request.url()).pathname === callbackPath) callbackRequests.push(request.url());
    });

    // The sign-in page is not served: no shell, no SSO button, no tenant
    // branding. The answer does not name the classification either.
    const signin = await page.goto(`${unverifiedOrigin}/signin`);
    if (!signin) throw new Error(`no response for ${unverifiedOrigin}/signin`);
    expect(signin.status()).toBe(404);
    expect(signin.headers()['cache-control']).toBe('no-store');
    expect(signin.headers()['o-domain-strategy']).toBeUndefined();
    expect(await signin.text()).toBe(NOT_CONFIGURED);

    // Start SSO the way SsoButton does (submitSsoLogin: a top-level form POST
    // of shrimp / redirect / connect), from the document the host returned.
    // The form is pinned above the page so nothing intercepts the click. A
    // real click submits it: form.submit() inside page.evaluate would race
    // the navigation it starts against the evaluate's own result.
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

    const [initiation] = await Promise.all([
      page.waitForResponse(
        (candidate) =>
          candidate.request().method() === 'POST' &&
          new URL(candidate.url()).pathname === initiationPath
      ),
      page.getByTestId('unverified-sso-initiation').getByRole('button').click(),
    ]);

    // The initiation gets the same 404: no redirect to the (mock) IdP, to the
    // sign-in page, or through platform credentials.
    expect(initiation.status()).toBe(404);
    expect(initiation.headers()['location']).toBeUndefined();
    expect(await initiation.text()).toBe(NOT_CONFIGURED);
    await page.waitForLoadState('domcontentloaded');
    expect(new URL(page.url()).origin).toBe(unverifiedOrigin);

    expect(callbackRequests).toEqual([]);
  });
});
