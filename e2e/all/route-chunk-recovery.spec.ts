// e2e/all/route-chunk-recovery.spec.ts
//
// A lazy route whose chunk fails to load, the usual cause being cached HTML
// that names chunks a deployment replaced. The page reloads once
// (src/utils/preloadError.ts) under the ADR-046 forced page load bound, one
// per tab per minute. When the reload is refused, or the browser asks before
// unloading a page with unsubmitted input and the visitor keeps the page, the
// navigation fails in place and RouteLoadNotice says so, with a manual reload
// button (src/utils/routeLoadFailure.ts).
//
// The failure is on record before reload() is called, which is why the notice
// is there when a cancelled beforeunload prompt leaves the page up: browsers
// do not report the cancellation, so the state has to be entered first
// (ADR-046 "Forced page load"). The prompt itself is the browser's own, shown
// only once the visitor has interacted with the page, so each test that needs
// it types the draft with real key events.
//
// Each test aborts the sign-in view's chunk with page.route(): /signin is a
// lazy route reachable from the masthead by every anonymous visitor.
//
// Requirements: a production build (the chunk names exist only there; vite
// dev serves modules by source path). CI runs this directory in the `simple`
// lane of .github/workflows/e2e.yml.

import { test as base, expect, type Page, type Request } from '@playwright/test';

import { FRESH_CONTEXT, waitForAppReady } from '../support/auth-journey';

/** src/utils/forcedPageLoad.ts FORCED_RELOAD_MARKER: when this tab last force-reloaded. */
const FORCED_RELOAD_MARKER = 'ots_forced_reload_at';

/**
 * How long to watch for a reload once a failure has settled. The recovery
 * handler reloads within milliseconds of a failure, so a reload would show
 * up well inside this window.
 */
const RELOAD_WINDOW_MS = 5_000;

/**
 * The production chunk of the sign-in view (src/apps/session/views/Login.vue).
 * vite.config.ts emits lazy chunks as `assets/[name]-[hash].js`, named after
 * the module, so the view becomes /dist/assets/Login-<8-character hash>.js.
 * The fixed hash length keeps it from matching another chunk whose name
 * starts with `Login-`.
 */
const LOGIN_CHUNK = /\/assets\/Login-[A-Za-z0-9_-]{8}\.js$/;

const DRAFT = 'typed before the link was clicked';

interface FailedChunk {
  /** How many times the browser has asked for the chunk. */
  readonly count: number;
  /** Waits until the browser has asked for the chunk at least once. */
  requested(): Promise<void>;
}

const test = base.extend<{
  /** Aborts every request for the sign-in view's chunk, as an unreachable asset host would. */
  failLoginChunk: () => Promise<FailedChunk>;
}>({
  failLoginChunk: async ({ page }, use) => {
    await use(async () => {
      let count = 0;
      await page.route(
        (url) => LOGIN_CHUNK.test(url.pathname),
        async (route) => {
          count += 1;
          await route.abort('failed');
        }
      );
      return {
        get count() {
          return count;
        },
        requested: () =>
          expect
            .poll(() => count, {
              message:
                'the browser requests the sign-in chunk (/dist/assets/Login-<hash>.js). ' +
                'If it never does, check the chunk name in public/web/dist/.vite/manifest.json.',
              timeout: 30_000,
            })
            .toBeGreaterThan(0),
      };
    });
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  },
});

function isDocumentRequest(request: Request): boolean {
  return request.isNavigationRequest() && request.resourceType() === 'document';
}

/** Path and query of every document request: one per page load. */
function recordDocumentRequests(page: Page): string[] {
  const urls: string[] = [];
  page.on('request', (request) => {
    if (!isDocumentRequest(request)) return;
    const url = new URL(request.url());
    urls.push(url.pathname + url.search);
  });
  return urls;
}

/**
 * Records the type of every browser dialog and dismisses it. Dismissing a
 * beforeunload prompt keeps the page, as a visitor choosing to stay does.
 * (Playwright dismisses dialogs by itself when nothing listens; this makes
 * the prompt an assertion.)
 */
function dismissDialogs(page: Page): string[] {
  const types: string[] = [];
  page.on('dialog', async (dialog) => {
    types.push(dialog.type());
    await dialog.dismiss();
  });
  return types;
}

/**
 * Marks the tab as having force-reloaded just now, before any app script runs,
 * so the forced page load bound (one per tab per minute) refuses the reload a
 * failed chunk would otherwise trigger.
 */
async function spendForcedReload(page: Page): Promise<void> {
  await page.addInitScript((key) => {
    try {
      if (sessionStorage.getItem(key) === null) sessionStorage.setItem(key, String(Date.now()));
    } catch {
      // about:blank has no storage.
    }
  }, FORCED_RELOAD_MARKER);
}

/** Waits out the window in which the recovery handler would reload. */
async function waitOutReloadWindow(page: Page): Promise<void> {
  await page
    .waitForRequest(isDocumentRequest, { timeout: RELOAD_WINDOW_MS })
    .catch(() => undefined);
}

function routeNotice(page: Page) {
  return page.getByTestId('route-load-notice');
}

function secretInput(page: Page) {
  return page.getByTestId('secret-content-input');
}

async function openHomepage(page: Page): Promise<void> {
  await page.goto('/');
  await waitForAppReady(page);
  await expect(page.getByTestId('header-signin-link')).toBeVisible();
  await expect(routeNotice(page)).toHaveCount(0);
}

/** Starts the in-app navigation to /signin; the failed chunk means it never completes. */
async function clickSignIn(page: Page): Promise<void> {
  await page.getByTestId('header-signin-link').click({ noWaitAfter: true });
}

/**
 * The notice for a page that could not open: an alert with a reload button
 * and a dismiss button, on the page the visitor was on, with its URL.
 */
async function expectRouteNotice(page: Page): Promise<void> {
  const notice = routeNotice(page);
  await expect(notice).toBeVisible();
  await expect(notice).toHaveAttribute('role', 'alert');
  await expect(notice.getByTestId('route-load-notice-reload')).toHaveText('Reload page');
  await expect(notice.getByTestId('route-load-notice-dismiss')).toBeVisible();
  await expect(page).toHaveURL('/');
}

test.use({ ...FRESH_CONTEXT, locale: 'en-US' });

test.describe('a route chunk that fails to load', () => {
  test('reloads the page once; the reloaded page stays where the visitor was', async ({
    page,
    failLoginChunk,
  }) => {
    const documents = recordDocumentRequests(page);
    await openHomepage(page);
    const login = await failLoginChunk();

    await clickSignIn(page);
    await login.requested();

    await expect
      .poll(() => documents.length, { message: 'the failed chunk reloads the page once' })
      .toBe(2);
    await waitOutReloadWindow(page);
    // The navigation never completed, so the reload is of the page the
    // visitor was on, and the reloaded page does not ask for the chunk again.
    expect(documents, 'exactly one recovery reload, of the same page').toEqual(['/', '/']);
    expect(login.count, 'the reloaded page does not ask for the chunk').toBe(1);

    await waitForAppReady(page);
    await expect(page.locator('html')).not.toHaveAttribute('data-app-failed');
    await expect(page).toHaveURL('/');
    await expect(routeNotice(page)).toHaveCount(0);
  });

  test('with the forced reload spent, the navigation fails in place and the notice offers a reload', async ({
    page,
    failLoginChunk,
  }) => {
    await spendForcedReload(page);
    const documents = recordDocumentRequests(page);
    await openHomepage(page);
    const login = await failLoginChunk();

    await clickSignIn(page);
    await login.requested();

    await expectRouteNotice(page);
    await waitOutReloadWindow(page);
    expect(documents, 'no reload: the bound refused it').toEqual(['/']);
    await expect(routeNotice(page)).toBeVisible();

    await routeNotice(page).getByTestId('route-load-notice-dismiss').click();
    await expect(routeNotice(page)).toHaveCount(0);
    await expect(page).toHaveURL('/');
  });

  // The visitor has typed a secret, so the browser asks before the recovery
  // reload would unload the page. Choosing to stay must not leave the failed
  // link unexplained: the notice is on record before reload() is called.
  test('with a draft on the page, cancelling the reload prompt keeps the draft and shows the notice', async ({
    page,
    failLoginChunk,
  }) => {
    const documents = recordDocumentRequests(page);
    const dialogs = dismissDialogs(page);
    await openHomepage(page);
    // Real key events: the beforeunload prompt needs the page to have been
    // interacted with (sticky activation), and the guard needs content.
    await secretInput(page).click();
    await page.keyboard.type(DRAFT);
    await expect(secretInput(page)).toHaveValue(DRAFT);
    const login = await failLoginChunk();

    await clickSignIn(page);
    await login.requested();

    await expect
      .poll(() => dialogs, { message: 'the browser asks before unloading the draft' })
      .toEqual(['beforeunload']);
    await expectRouteNotice(page);
    await waitOutReloadWindow(page);
    expect(documents, 'the page stayed: no reload').toEqual(['/']);
    expect(dialogs, 'nothing is retried: one prompt').toEqual(['beforeunload']);

    await expect(routeNotice(page)).toBeVisible();
    await expect(secretInput(page), 'the draft survives').toHaveValue(DRAFT);
    await expect(page).toHaveURL('/');
  });
});
