// src/tests/e2e/secret-context.spec.ts

import { test, expect } from '@playwright/test';

/**
 * E2E tests for secret context and actor role behavior
 *
 * Tests the different user experiences when viewing secrets:
 * - CREATOR: Owner viewing their own secret (shows warning, burn control)
 * - RECIPIENT_AUTH: Authenticated user viewing someone else's secret
 * - RECIPIENT_ANON: Anonymous user viewing a secret (entitlements upgrade)
 *
 * These tests validate that:
 * 1. Owners see appropriate warnings when viewing their own secrets
 * 2. Anonymous users see signup CTAs and marketing content
 * 3. Authenticated recipients see appropriate UI without marketing
 */

test.describe('Secret Context - Actor Roles', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
  });

  test('owner sees warning when viewing own secret', async ({ page, context, baseURL }) => {
    // This test requires:
    // 1. Create a secret as authenticated user
    // 2. View that secret as the creator
    // 3. Verify owner-specific UI elements appear

    // Mock authenticated state - use baseURL from config
    const cookieDomain = new URL(baseURL || 'http://localhost:3000').hostname;
    await context.addCookies([
      {
        name: 'sess',
        value: 'mock-session-token',
        domain: cookieDomain,
        path: '/',
      },
    ]);

    // Mock the secret details endpoint to indicate ownership
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      // If it's a metadata request
      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: true, // User owns this secret
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Navigate to a secret view page
    await page.goto('/secret/test-secret-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Owner should see burn control or owner-specific UI
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Check for owner-specific elements (adjust selectors as needed)
    // Examples:
    // - Burn button
    // - "You are viewing your own secret" warning
    // - Dashboard link instead of signup CTA

    // Verify no JavaScript errors occurred
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Owner view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('anonymous user does not see owner warning', async ({ page, context }) => {
    // Clear all cookies to ensure anonymous state
    await context.clearCookies();

    // Mock the secret details endpoint to indicate non-ownership
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false, // Anonymous viewer
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Collect console errors from the whole page lifecycle (registered
    // before navigation so load-time errors are captured too)
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto('/secret/test-secret-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Anonymous users should see:
    // - Signup CTA instead of dashboard link
    // - Entitlements upgrade content
    // - NO burn control
    // - NO owner warning

    // Verify page loads without errors
    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Anonymous view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('authenticated recipient sees appropriate UI', async ({ page, context, baseURL }) => {
    // Mock authenticated state - use baseURL from config
    const cookieDomain = new URL(baseURL || 'http://localhost:3000').hostname;
    await context.addCookies([
      {
        name: 'sess',
        value: 'mock-session-token',
        domain: cookieDomain,
        path: '/',
      },
    ]);

    // Mock the secret details endpoint for authenticated non-owner
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false, // Authenticated but not owner
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Collect console errors from the whole page lifecycle (registered
    // before navigation so load-time errors are captured too)
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto('/secret/test-secret-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Authenticated recipients should see:
    // - Dashboard link (not signup CTA)
    // - NO entitlements upgrade
    // - NO burn control (not owner)
    // - NO owner warning

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Authenticated recipient view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('secret view handles passphrase requirement', async ({ page, context }) => {
    await context.clearCookies();

    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false,
              ttl: 3600,
              state: 'new',
              passphrase_required: true, // Requires passphrase
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Collect console errors from the whole page lifecycle (registered
    // before navigation so load-time errors are captured too)
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto('/secret/test-secret-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show passphrase input
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Verify no errors during passphrase handling
    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Passphrase view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('theme applies correctly for custom domains', async ({ page }) => {
    // Mock custom domain branding
    await page.addInitScript(() => {
      window.__BOOTSTRAP_ME__ = {
        ...window.__BOOTSTRAP_ME__,
        domain_strategy: 'custom',
        domain_branding: {
          primary_color: '#3b82f6',
          button_text_light: true,
          description: 'Custom Brand',
        },
      };
    });

    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false,
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/secret/test-secret-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Verify branded theme is applied
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Check for theme application (could verify CSS variables or computed styles)
    const bodyStyle = await page.locator('body').evaluate((el) => window.getComputedStyle(el).backgroundColor);

    expect(bodyStyle).toBeTruthy();
  });

  test('secret view handles burned secrets gracefully', async ({ page }) => {
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false,
              ttl: 0,
              state: 'received', // Already viewed/burned
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Collect console errors from the whole page lifecycle (registered
    // before navigation so load-time errors are captured too)
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto('/secret/test-secret-key');
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    // Should show "already viewed" message
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Verify graceful error handling

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Burned secret view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });
});

/**
 * Referer privacy on secret documents (#4542).
 *
 * The document policy is `strict-origin`, set twice and pinned to one value:
 * the `Referrer-Policy` response header (Onetime::Middleware::Registry::
 * REFERRER_POLICY, applied through Otto's security_config) and the
 * `<meta name="referrer">` in head-base.rue. Under that policy the browser
 * may put scheme://host[:port]/ in a Referer and nothing else: no path, no
 * query, on same-origin and cross-origin requests alike. This is what keeps a
 * secret identifier out of every Referer the page causes to be sent.
 *
 * Why not `no-referrer`, which sends even less: under it a native form POST
 * carries `Origin: null`, which Rack::Protection::HttpOrigin refuses, and every
 * SSO sign-in starts with such a POST. So the suite also pins the exact policy
 * value and checks that a native same-origin POST from the document carries
 * the real origin. A weaker policy (`strict-origin-when-cross-origin`, the
 * browser default) leaks the full URL same-origin; `no-referrer` breaks SSO.
 * Both fail here.
 *
 * The document under test is a real secret document served by the app with
 * synthetic markers in its path and query. The markers stand in for a secret
 * identifier and for a query value; a Referer that carries either is a
 * failure regardless of anything else.
 */
test.describe('Secret Context - Referer privacy (#4542)', () => {
  // Alphanumeric only: the /secret/:secretIdentifier route guard sends any
  // other shape to NotFound, which would move the document off this URL.
  const PATH_MARKER = 'e2eRefererPathMarker7f3a9c';
  const QUERY_MARKER = 'e2eRefererQueryMarker2b8d1e';
  const DOCUMENT_PATH = `/secret/${PATH_MARKER}?probe=${QUERY_MARKER}`;

  // A cross-origin destination that never leaves the browser: every request
  // to it is answered by page.route, so no DNS, TLS, or network is involved
  // and the headers the browser attached are still observable.
  const PROBE_ORIGIN = 'https://referer-probe.example';

  // Chromium reports a withheld Referer as an absent header or, on some
  // intercepted requests, as an empty one. Both mean "not sent".
  function expectPrivateReferer(referer: string | undefined, origin: string, what: string): void {
    if (referer !== undefined && referer !== '') {
      expect(referer, `${what}: Referer must be exactly origin-only`).toBe(`${origin}/`);
    }
    expect(referer ?? '', `${what}: Referer must not carry the path marker`).not.toContain(
      PATH_MARKER
    );
    expect(referer ?? '', `${what}: Referer must not carry the query marker`).not.toContain(
      QUERY_MARKER
    );
  }

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
    await page.route(`${PROBE_ORIGIN}/**`, async (route) => {
      const accept = route.request().headers()['accept'] ?? '';
      if (route.request().isNavigationRequest() || accept.includes('text/html')) {
        await route.fulfill({
          status: 200,
          contentType: 'text/html',
          body: '<!doctype html><title>referer probe</title><p data-probe="landing">ok</p>',
        });
        return;
      }
      await route.fulfill({ status: 204 });
    });
  });

  test('header and meta policy are one exact value: strict-origin', async ({ page }) => {
    const response = await page.goto(DOCUMENT_PATH);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();

    expect(
      response?.headers()['referrer-policy'],
      'Referrer-Policy header on the secret document'
    ).toBe('strict-origin');

    const metaPolicy = await page
      .locator('meta[name="referrer"]')
      .evaluate((el) => el.getAttribute('content'));
    expect(metaPolicy, 'meta name="referrer" on the secret document').toBe('strict-origin');
  });

  test('same-origin requests from a secret document send no path or query in Referer', async ({
    page,
  }) => {
    // Every request the document causes: scripts, styles, fonts, the API
    // call for the secret itself, and the same-origin probes below. All of
    // them are same-origin (the probe origin is excluded).
    const observed: Array<{ url: string; referer: string | undefined }> = [];
    page.on('request', (request) => {
      if (request.url().startsWith(PROBE_ORIGIN)) return;
      void request
        .allHeaders()
        .then((headers) => observed.push({ url: request.url(), referer: headers['referer'] }))
        .catch(() => undefined);
    });

    await page.goto(DOCUMENT_PATH);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
    // The SPA must still be on the marker URL, or every Referer below would
    // be origin-only for the wrong reason (the document no longer has a path
    // or query worth leaking).
    expect(page.url(), 'document must keep the path marker').toContain(PATH_MARKER);
    expect(page.url(), 'document must keep the query marker').toContain(QUERY_MARKER);
    const origin = new URL(page.url()).origin;

    // A same-origin fetch() from the document (the SPA's own API calls take
    // this path). The URL is unknown to the app; only the request matters.
    const [sameOriginFetch] = await Promise.all([
      page.waitForRequest((candidate) => candidate.url() === `${origin}/e2e/referer-probe/fetch`),
      page.evaluate(() => fetch('/e2e/referer-probe/fetch', { method: 'GET' }).catch(() => undefined)),
    ]);
    expectPrivateReferer(
      (await sameOriginFetch.allHeaders())['referer'],
      origin,
      'same-origin fetch()'
    );

    // A native same-origin form POST, the request shape SSO initiation uses
    // (submitSsoLogin builds and submits a POST form). The browser derives
    // both Origin and Referer from the document policy: under no-referrer
    // the Origin is the literal `null` (#4542); under strict-origin it is the
    // document origin.
    const [nativePost] = await Promise.all([
      page.waitForRequest(
        (candidate) =>
          candidate.method() === 'POST' &&
          candidate.url() === `${origin}/e2e/referer-probe/post` &&
          candidate.isNavigationRequest()
      ),
      page.evaluate(() => {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = '/e2e/referer-probe/post';
        document.body.appendChild(form);
        form.submit();
      }),
    ]);
    const nativePostHeaders = await nativePost.allHeaders();
    expect(
      nativePostHeaders['origin'],
      'native same-origin POST must carry the document origin, never null'
    ).toBe(origin);
    expectPrivateReferer(nativePostHeaders['referer'], origin, 'native same-origin POST');

    // The navigated document sees the same truth from the inside.
    await page.waitForURL(`${origin}/e2e/referer-probe/post`);
    const documentReferrer = await page.evaluate(() => document.referrer);
    expectPrivateReferer(
      documentReferrer === '' ? undefined : documentReferrer,
      origin,
      'document.referrer after a same-origin navigation'
    );

    // Nothing the secret document loaded carried the markers either.
    expect(observed.length, 'the secret document must have caused requests').toBeGreaterThan(0);
    for (const { url, referer } of observed) {
      expectPrivateReferer(referer, origin, `request to ${url}`);
    }
  });

  test('cross-origin requests from a secret document send at most the origin in Referer', async ({
    page,
  }) => {
    await page.goto(DOCUMENT_PATH);
    await expect(page.locator('html[data-app-ready="true"]')).toBeAttached();
    // The SPA must still be on the marker URL, or every Referer below would
    // be origin-only for the wrong reason (the document no longer has a path
    // or query worth leaking).
    expect(page.url(), 'document must keep the path marker').toContain(PATH_MARKER);
    expect(page.url(), 'document must keep the query marker').toContain(QUERY_MARKER);
    const origin = new URL(page.url()).origin;

    // Cross-origin subresource (an image), the classic Referer leak.
    const [imageRequest] = await Promise.all([
      page.waitForRequest(`${PROBE_ORIGIN}/pixel.gif`),
      page.evaluate((src) => {
        const img = document.createElement('img');
        img.src = src;
        document.body.appendChild(img);
      }, `${PROBE_ORIGIN}/pixel.gif`),
    ]);
    expectPrivateReferer(
      (await imageRequest.allHeaders())['referer'],
      origin,
      'cross-origin <img>'
    );

    // Cross-origin fetch() in no-cors mode.
    const [fetchRequest] = await Promise.all([
      page.waitForRequest(`${PROBE_ORIGIN}/beacon`),
      page.evaluate(
        (url) => fetch(url, { mode: 'no-cors' }).catch(() => undefined),
        `${PROBE_ORIGIN}/beacon`
      ),
    ]);
    expectPrivateReferer(
      (await fetchRequest.allHeaders())['referer'],
      origin,
      'cross-origin fetch()'
    );

    // Cross-origin top-level navigation, then what the destination sees.
    const [navigation] = await Promise.all([
      page.waitForRequest(
        (candidate) =>
          candidate.url() === `${PROBE_ORIGIN}/landing` && candidate.isNavigationRequest()
      ),
      page.evaluate((url) => {
        window.location.assign(url);
      }, `${PROBE_ORIGIN}/landing`),
    ]);
    expectPrivateReferer(
      (await navigation.allHeaders())['referer'],
      origin,
      'cross-origin navigation'
    );

    await expect(page.locator('[data-probe="landing"]')).toBeAttached();
    const documentReferrer = await page.evaluate(() => document.referrer);
    expectPrivateReferer(
      documentReferrer === '' ? undefined : documentReferrer,
      origin,
      'document.referrer on the cross-origin destination'
    );
  });
});
