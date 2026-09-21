// e2e/all/auth-hydration.spec.ts
//
// #4456: hydration is the canonical initial snapshot.
//
// The server injects a complete bootstrap payload before Vue mounts, so a page
// load must not ask GET /bootstrap/me again. Before #4456 MastHead refreshed
// unconditionally on mount and the route guard awaited a check whenever the
// last one was old, so every page load made at least one such request.
//
// These scenarios need no account and run against any authentication mode.
// The authenticated counterparts live in e2e/auth/session-consistency.spec.ts.
//
// Usage:
//   PLAYWRIGHT_BASE_URL=https://dev.onetime.dev \
//     pnpm test:playwright e2e/all/auth-hydration.spec.ts --project=chromium

import { expect, test, type Page } from '@playwright/test';

import { waitForAppReady } from '../support/auth-journey';

const BOOTSTRAP_PATH = '/bootstrap/me';

// "Startup is over" is waitForAppReady(): the flag is set after mount AND
// router.isReady(), i.e. after both places that used to fetch (MastHead's
// onMounted and the initial navigation guard). Requests are recorded when
// ISSUED, so by then a startup request would already have been seen.

/**
 * Records every GET /bootstrap/me the page makes.
 *
 * Attach BEFORE navigating: a listener added after `goto` would miss exactly
 * the startup request these tests exist to catch.
 */
function recordBootstrapRequests(page: Page): string[] {
  const seen: string[] = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname === BOOTSTRAP_PATH) seen.push(request.url());
  });
  return seen;
}

/** Main-frame navigations, in order. */
function recordNavigations(page: Page): string[] {
  const urls: string[] = [];
  page.on('framenavigated', (frame) => {
    if (frame === page.mainFrame()) urls.push(new URL(frame.url()).pathname);
  });
  return urls;
}

/**
 * Server-visible top-level navigations: one entry per document request the
 * browser sent. `framenavigated` fires per-commit and Chromium/Vue Router 4
 * legitimately produce multiple commits per logical page load (initial-URL
 * commit + history normalization + scroll-restoration replaceState), so it
 * cannot count "the browser committed X once". This can.
 */
function recordDocumentRequests(page: Page): string[] {
  const paths: string[] = [];
  page.on('request', (request) => {
    if (request.isNavigationRequest() && request.resourceType() === 'document') {
      paths.push(new URL(request.url()).pathname);
    }
  });
  return paths;
}

test.describe('hydration is the initial snapshot (#4456)', () => {
  test('an anonymous page load makes no /bootstrap/me request', async ({ page }) => {
    const bootstrapRequests = recordBootstrapRequests(page);

    await page.goto('/');
    await waitForAppReady(page);

    // The payload was consumed from the page, not fetched.
    expect(await page.evaluate(() => (window as { __BOOTSTRAP_ME__?: unknown }).__BOOTSTRAP_ME__)).toBe(
      true
    );
    expect(bootstrapRequests).toEqual([]);
  });

  test('the sign-in page makes no /bootstrap/me request on load', async ({ page }) => {
    const bootstrapRequests = recordBootstrapRequests(page);

    await page.goto('/signin');
    await waitForAppReady(page);

    expect(bootstrapRequests).toEqual([]);
  });

  test('/dashboard reaches /signin without a Vue bounce', async ({ page }) => {
    const bootstrapRequests = recordBootstrapRequests(page);
    const navigations = recordNavigations(page);
    const documentRequests = recordDocumentRequests(page);

    await page.goto('/dashboard');
    await waitForAppReady(page);

    // The server refuses protected HTML with a 302, so the browser commits
    // /signin directly. (What the Location carries is the server's business
    // and is covered by the Ruby failure-matrix specs, not asserted here.)
    expect(new URL(page.url()).pathname).toBe('/signin');

    // No bounce: the dashboard route never committed and nothing navigated
    // again once sign-in was reached. A bounce would show up as a /dashboard
    // entry, a last entry that is not /signin, or a second /signin document
    // request. Same-URL Vue-Router pushes emit framenavigated but no document
    // request, so counting requests is what actually catches a bounce.
    expect(navigations).not.toContain('/dashboard');
    expect(navigations.at(-1)).toBe('/signin');
    expect(documentRequests.filter((path) => path === '/signin')).toHaveLength(1);

    // And the decision needed no request: it came from the hydrated snapshot.
    expect(bootstrapRequests).toEqual([]);
  });

  test('client-side navigation is not a refresh trigger', async ({ page }) => {
    const bootstrapRequests = recordBootstrapRequests(page);

    await page.goto('/');
    await waitForAppReady(page);
    await page.goto('/signin');
    await waitForAppReady(page);
    await page.goBack();
    await waitForAppReady(page);

    expect(bootstrapRequests).toEqual([]);
  });
});
