// e2e/i18n/locale-loading.spec.ts
//
// Lazy-loaded locales: a visitor who asks for a language never sees English
// first.
//
// English ships in the entry bundle; every other locale is its own chunk
// (src/i18n.ts). The app must not mount until the locale chosen for the first
// navigation is loaded and active, a later switch must not show two languages
// at once, and a chunk that fails must fail visibly instead of falling back
// to English. Each test holds or aborts a locale chunk with page.route(), so
// the window in which English could appear lasts as long as the test wants.
//
// A failed chunk reloads the page once (src/utils/preloadError.ts): the usual
// cause is cached HTML naming chunks a deployment replaced. The reload goes
// through the ADR-046 forced page load bound, one per tab per minute, so a
// chunk that keeps failing ends in the shell's failure notice instead of a
// reload loop.
//
// "First content" is measured in the page: an init script records every
// distinct state of #app from the first byte (see recordAppStates). Vue sets
// data-v-app on #app at the end of mount, so the first recorded state with
// that attribute is exactly what the first render produced.
//
// Requirements:
//   - A production build. The chunk names exist only there (vite dev serves
//     the JSON modules by source path).
//   - A server with I18N_ENABLED=true. With i18n off the server offers only
//     'en' (lib/onetime/initializers/load_locales.rb) and hides the language
//     toggle, so there is nothing to load. Each test asserts this first and
//     fails with that reason rather than skipping.
//
// CI runs this directory in the `i18n` lane of .github/workflows/e2e.yml
// (the production image, simple auth mode, I18N_ENABLED=true).
//
// Usage:
//   PLAYWRIGHT_BASE_URL=<server with I18N_ENABLED=true> \
//     pnpm test:playwright e2e/i18n/ --project=i18n

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { test as base, expect, type Page, type Request } from '@playwright/test';

import { FRESH_CONTEXT, waitForAppReady } from '../support/auth-journey';

// ---------------------------------------------------------------------------
// Expected copy
// ---------------------------------------------------------------------------

/**
 * The homepage heading for an anonymous visitor (HomepageTaglines.vue, an h1
 * rendered with t('web.homepage.tagline2')). Read from the committed
 * translation sources, not generated/locales/, which is gitignored and absent
 * in a fresh checkout.
 */
const MARKER_KEY = 'web.homepage.tagline2';
const LOCALE_SOURCES = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../locales/content'
);

function markerText(code: string): string {
  const file = path.join(LOCALE_SOURCES, code, 'secret-homepage.json');
  const entries = JSON.parse(readFileSync(file, 'utf8')) as Record<string, { text?: string }>;
  const text = entries[MARKER_KEY]?.text;
  if (!text) throw new Error(`${file} has no "${MARKER_KEY}" text`);
  return text;
}

/** bg is the locale from the original report; nl is a second, unrelated one. */
const MARKERS = {
  en: markerText('en'),
  bg: markerText('bg'),
  nl: markerText('nl'),
} as const;
type Code = keyof typeof MARKERS;

// A shared value would let one locale pass for another.
if (new Set(Object.values(MARKERS)).size !== Object.keys(MARKERS).length) {
  throw new Error(`"${MARKER_KEY}" must differ between ${Object.keys(MARKERS).join(', ')}`);
}

/** src/shared/stores/languageStore.ts SESSION_STORAGE_KEY */
const SESSION_STORAGE_KEY = 'selected.locale';
const UPDATE_LOCALE_PATH = '/api/account/update-locale';

/**
 * How long to watch for a further reload once a failure has settled. The
 * recovery handler reloads within milliseconds of a failure, so another
 * reload would show up well inside this window, which in turn stays inside
 * the handler's own 10-second limit.
 */
const RELOAD_WINDOW_MS = 5_000;

// ---------------------------------------------------------------------------
// Locale chunks
// ---------------------------------------------------------------------------

/**
 * Matches the production chunk of one lazily loaded locale. vite.config.ts
 * emits lazy chunks as `assets/[name]-[hash].js` (served under /dist), and
 * Rolldown names a dynamic-import chunk after its module, so
 * generated/locales/bg.json becomes /dist/assets/bg-<8-character hash>.js.
 * The fixed hash length keeps `bg` from matching some other chunk whose name
 * starts with `bg-`.
 */
function isLocaleChunk(code: string): (url: URL) => boolean {
  const pattern = new RegExp(`/assets/${code}-[A-Za-z0-9_-]{8}\\.js$`);
  return (url) => pattern.test(url.pathname);
}

interface ChunkRoute {
  /** Waits until the browser has asked for the chunk at least once. */
  requested(): Promise<void>;
  /** How many times the browser has asked for it. */
  readonly count: number;
}

interface HeldChunk extends ChunkRoute {
  /** Lets the held request, and any later one, through to the server. */
  release(): void;
}

function chunkRoute(code: string, counter: () => number): ChunkRoute {
  return {
    get count() {
      return counter();
    },
    requested: () =>
      expect
        .poll(counter, {
          message:
            `the browser requests the ${code} locale chunk (/dist/assets/${code}-<hash>.js). ` +
            'If it never does, check the chunk name in public/web/dist/.vite/manifest.json.',
          timeout: 30_000,
        })
        .toBeGreaterThan(0),
  };
}

const test = base.extend<{
  localeChunks: {
    /** Holds every request for the chunk until release(). */
    hold(code: string): Promise<HeldChunk>;
    /** Aborts every request for the chunk, as an unreachable asset host would. */
    fail(code: string): Promise<ChunkRoute>;
  };
}>({
  localeChunks: async ({ page }, use) => {
    const releases: Array<() => void> = [];

    await use({
      async hold(code) {
        let release!: () => void;
        const released = new Promise<void>((resolve) => {
          release = resolve;
        });
        releases.push(release);
        let count = 0;
        await page.route(isLocaleChunk(code), async (route) => {
          count += 1;
          await released;
          // The page is gone if the test already ended.
          await route.continue().catch(() => undefined);
        });
        // Object.assign, not a spread: a spread would copy `count` once
        // instead of keeping its getter.
        return Object.assign(
          chunkRoute(code, () => count),
          { release }
        );
      },

      async fail(code) {
        let count = 0;
        await page.route(isLocaleChunk(code), async (route) => {
          count += 1;
          await route.abort('failed');
        });
        return chunkRoute(code, () => count);
      },
    });

    // No route handler may outlive the test.
    releases.forEach((release) => release());
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  },
});

// ---------------------------------------------------------------------------
// In-page recording
// ---------------------------------------------------------------------------

/** One distinct state of #app, as the in-page recorder saw it. */
interface AppState {
  /** performance.now() in the page when the state was first seen. */
  at: number;
  /** Vue has mounted: it sets data-v-app on #app once the first render is in. */
  mounted: boolean;
  /** The server-rendered loading shell is still inside #app. */
  shell: boolean;
  /** lang on the layout root, which App.vue binds to the active i18n locale. */
  lang: string | null;
  /** The locales whose heading text #app contains. */
  copy: string[];
}

/**
 * Records every distinct state of #app from the start of each document.
 * Install BEFORE navigating. Returns a reader for the current document's
 * states.
 *
 * The observer is attached to `document` because #app does not exist yet
 * when init scripts run. Mutation callbacks are delivered after the task that
 * caused them, so the batch that contains Vue's mount (clear #app, render,
 * set data-v-app) is seen as one state: the first content.
 */
async function recordAppStates(page: Page): Promise<() => Promise<AppState[]>> {
  await page.addInitScript((markers: Record<string, string>) => {
    const states: unknown[] = [];
    (window as unknown as { __appStates: unknown[] }).__appStates = states;
    let previous = '';

    const record = () => {
      const app = document.getElementById('app');
      if (!app) return;
      const text = app.textContent ?? '';
      const state = {
        mounted: app.hasAttribute('data-v-app'),
        shell: app.querySelector('.app-fallback') !== null,
        lang: app.querySelector('[data-testid="base-layout"]')?.getAttribute('lang') ?? null,
        copy: Object.keys(markers).filter((code) => text.includes(markers[code])),
      };
      const signature = JSON.stringify(state);
      if (signature === previous) return;
      previous = signature;
      states.push({ at: performance.now(), ...state });
    };

    new MutationObserver(record).observe(document, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ['data-v-app', 'lang'],
    });
  }, MARKERS);

  return () =>
    page.evaluate(() => (window as unknown as { __appStates?: AppState[] }).__appStates ?? []);
}

/** States in which the heading is in one language and the active locale another. */
function mixedStates(states: AppState[]): AppState[] {
  return states.filter(
    (state) =>
      state.mounted &&
      state.copy.length > 0 &&
      (state.copy.length !== 1 || state.copy[0] !== state.lang)
  );
}

/** The page's clock, for comparing against AppState.at. */
function pageNow(page: Page): Promise<number> {
  return page.evaluate(() => performance.now());
}

/**
 * Lets the page render `frames` animation frames. Used only before asserting
 * that something has NOT happened while a chunk is held: the hold must last
 * long enough for a premature mount or switch to show up. It counts frames,
 * not milliseconds, and ends once the page has rendered them.
 */
async function renderFrames(page: Page, frames = 10): Promise<void> {
  await page.evaluate(
    (count) =>
      new Promise<void>((resolve) => {
        let seen = 0;
        const tick = () => {
          seen += 1;
          if (seen >= count) resolve();
          else requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      }),
    frames
  );
}

// ---------------------------------------------------------------------------
// Network recording
// ---------------------------------------------------------------------------

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

/** The locale of every POST that saves a language preference on the server. */
function recordSavedLocales(page: Page): string[] {
  const locales: string[] = [];
  page.on('request', (request) => {
    if (request.method() !== 'POST') return;
    if (new URL(request.url()).pathname !== UPDATE_LOCALE_PATH) return;
    let body: { locale?: unknown } | null = null;
    try {
      body = request.postDataJSON() as { locale?: unknown } | null;
    } catch {
      // Recorded below as an unreadable body.
    }
    locales.push(String(body?.locale ?? '<unreadable body>'));
  });
  return locales;
}

/** URLs of every request for one locale's chunk, without intercepting it. */
function recordChunkRequests(page: Page, code: string): string[] {
  const matches = isLocaleChunk(code);
  const urls: string[] = [];
  page.on('request', (request) => {
    if (matches(new URL(request.url()))) urls.push(request.url());
  });
  return urls;
}

// ---------------------------------------------------------------------------
// Page helpers
// ---------------------------------------------------------------------------

/**
 * Fails the test unless the server offers these locales. Reads the payload
 * the server rendered, not window.__BOOTSTRAP_ME__, which the app replaces
 * with `true` at startup (same approach as support/diagnostics-guard.ts).
 */
async function expectLocalesServed(page: Page, codes: string[]): Promise<void> {
  const payload = await page.locator('script[data-window="__BOOTSTRAP_ME__"]').textContent();
  const bootstrap = JSON.parse(payload ?? '{}') as {
    i18n_enabled?: unknown;
    supported_locales?: unknown;
  };
  expect(
    bootstrap.i18n_enabled,
    'the target runs with I18N_ENABLED=true (this suite cannot run against an i18n-off server)'
  ).toBe(true);
  expect(bootstrap.supported_locales, `the target supports ${codes.join(', ')}`).toEqual(
    expect.arrayContaining(codes)
  );
}

/** Seeds the stored language selection before any app script runs. */
async function seedStoredLocale(page: Page, code: Code): Promise<void> {
  await page.addInitScript(
    ([key, value]) => {
      try {
        // Seed once: a later document in the same test sees what the app wrote.
        if (sessionStorage.getItem(key) === null) sessionStorage.setItem(key, value);
      } catch {
        // about:blank has no storage.
      }
    },
    [SESSION_STORAGE_KEY, code] as const
  );
}

function storedLocale(page: Page): Promise<string | null> {
  return page.evaluate((key) => sessionStorage.getItem(key), SESSION_STORAGE_KEY);
}

function heading(page: Page, code: Code) {
  return page.getByRole('heading', { name: MARKERS[code], exact: true });
}

function layoutRoot(page: Page) {
  return page.getByTestId('base-layout');
}

/**
 * The document element. Its lang is the server's BCP 47 tag for the request's
 * locale until the app activates one; from then on the app keeps it on the
 * active locale, so teleported content (modals, toasts) is labelled too.
 */
function htmlElement(page: Page) {
  return page.locator('html');
}

/**
 * Waits for the one recovery reload a failed chunk triggers, then for the
 * outcome on the reloaded page. Ends early if the page reloads again;
 * otherwise waits out RELOAD_WINDOW_MS.
 */
async function waitOutReloads(page: Page, documents: string[]): Promise<void> {
  await expect
    .poll(() => documents.length, { message: 'the failed chunk reloads the page once' })
    .toBeGreaterThanOrEqual(2);
  await page
    .waitForRequest(isDocumentRequest, { timeout: RELOAD_WINDOW_MS })
    .catch(() => undefined);
}

/** The app has not mounted: #app still holds the server-rendered shell. */
async function expectShellOnly(page: Page): Promise<void> {
  await expect(page.locator('#app .app-fallback')).toBeAttached();
  await expect(page.locator('#app')).not.toHaveAttribute('data-v-app');
  await expect(page.locator('html')).not.toHaveAttribute('data-app-ready');
  await expect(page.locator('html')).not.toHaveAttribute('data-app-failed');
  for (const code of Object.keys(MARKERS) as Code[]) {
    await expect(heading(page, code)).toHaveCount(0);
  }
}

/**
 * Picks a language in the footer LanguageToggle. Escape first: a switch that
 * is still loading leaves the menu open, and clicking the toggle would then
 * close it instead of opening it.
 */
async function chooseLanguage(page: Page, code: Code): Promise<void> {
  await page.keyboard.press('Escape');
  // A test id, not the accessible name: the name is itself translated.
  await page.getByTestId('language-toggle').click();
  await page
    .getByRole('menuitem')
    .and(page.locator(`[lang="${code}"]`))
    .click();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// An English browser and empty storage: nothing but the URL or a seeded
// selection asks for another language.
test.use({ ...FRESH_CONTEXT, locale: 'en-US' });

test.describe('initial locale', () => {
  test('/?locale=bg renders Bulgarian as its first content while the bg chunk is delayed', async ({
    page,
    localeChunks,
  }) => {
    const states = await recordAppStates(page);
    const savedLocales = recordSavedLocales(page);
    const englishChunk = recordChunkRequests(page, 'en');
    const bg = await localeChunks.hold('bg');

    await page.goto('/?locale=bg', { waitUntil: 'commit' });
    await expectLocalesServed(page, ['bg']);
    await bg.requested();

    // While bg is held the server-rendered shell stays, and no app copy at all
    // (English included) is on the page. The server already labels the
    // document with the requested language.
    await renderFrames(page);
    await expectShellOnly(page);
    await expect(htmlElement(page)).toHaveAttribute('lang', 'bg');

    const releasedAt = await pageNow(page);
    bg.release();
    await waitForAppReady(page);

    const recorded = await states();
    expect(
      recorded.filter((state) => state.at < releasedAt && state.mounted),
      'the app did not mount while the bg chunk was held'
    ).toEqual([]);
    const first = recorded.find((state) => state.mounted);
    expect(first, 'the recorder saw the mount').toBeDefined();
    expect(first?.copy, 'the first content is Bulgarian, not English').toEqual(['bg']);
    expect(first?.lang, 'the first render runs with bg active').toBe('bg');
    expect(
      recorded.filter((state) => state.copy.includes('en')),
      'English never rendered'
    ).toEqual([]);

    await expect(heading(page, 'bg')).toBeVisible();
    await expect(layoutRoot(page)).toHaveAttribute('lang', 'bg');
    await expect(htmlElement(page)).toHaveAttribute('lang', 'bg');

    // A URL locale is remembered for the session but never saved to the
    // account: only the language toggle calls the update endpoint.
    expect(await storedLocale(page)).toBe('bg');
    expect(savedLocales, `?locale=bg makes no ${UPDATE_LOCALE_PATH} request`).toEqual([]);

    // English ships in the entry bundle.
    expect(englishChunk, 'English is not loaded as a separate chunk').toEqual([]);
  });

  test('a stored selection renders in that language from the first content', async ({
    page,
    localeChunks,
  }) => {
    await seedStoredLocale(page, 'nl');
    const states = await recordAppStates(page);
    const nl = await localeChunks.hold('nl');

    await page.goto('/', { waitUntil: 'commit' });
    await expectLocalesServed(page, ['nl']);
    await nl.requested();

    await renderFrames(page);
    await expectShellOnly(page);
    // The server knows nothing of the stored selection.
    await expect(htmlElement(page)).toHaveAttribute('lang', 'en');

    const releasedAt = await pageNow(page);
    nl.release();
    await waitForAppReady(page);

    const recorded = await states();
    expect(
      recorded.filter((state) => state.at < releasedAt && state.mounted),
      'the app did not mount while the nl chunk was held'
    ).toEqual([]);
    const first = recorded.find((state) => state.mounted);
    expect(first?.copy, 'the first content is Dutch').toEqual(['nl']);
    expect(first?.lang).toBe('nl');
    expect(
      recorded.filter((state) => state.copy.includes('en')),
      'English never rendered'
    ).toEqual([]);

    await expect(heading(page, 'nl')).toBeVisible();
    await expect(htmlElement(page)).toHaveAttribute('lang', 'nl');
    expect(await storedLocale(page)).toBe('nl');
  });

  test('?locale=bg wins over a stored selection, which is never loaded', async ({
    page,
    localeChunks,
  }) => {
    await seedStoredLocale(page, 'nl');
    const states = await recordAppStates(page);
    const dutchChunk = recordChunkRequests(page, 'nl');
    const bg = await localeChunks.hold('bg');

    await page.goto('/?locale=bg', { waitUntil: 'commit' });
    await expectLocalesServed(page, ['bg', 'nl']);
    await bg.requested();

    await renderFrames(page);
    await expectShellOnly(page);

    bg.release();
    await waitForAppReady(page);

    const recorded = await states();
    const first = recorded.find((state) => state.mounted);
    expect(first?.copy, 'the first content is Bulgarian: the URL locale wins').toEqual(['bg']);
    expect(first?.lang).toBe('bg');
    expect(
      recorded.filter((state) => state.copy.some((code) => code !== 'bg')),
      'neither the stored selection nor English ever rendered'
    ).toEqual([]);

    await expect(heading(page, 'bg')).toBeVisible();
    // The locale is resolved once, before loading: the losing selection is
    // not loaded and applied first.
    expect(dutchChunk, 'the stored nl selection is never loaded').toEqual([]);
    expect(await storedLocale(page), 'the URL locale replaces the stored one').toBe('bg');
  });

  // Locale codes are underscored; lang attributes take BCP 47 tags.
  test('?locale=pt_BR labels the document pt-BR, from the server and then the app', async ({
    page,
    localeChunks,
  }) => {
    const portuguese = await localeChunks.hold('pt_BR');

    await page.goto('/?locale=pt_BR', { waitUntil: 'commit' });
    await expectLocalesServed(page, ['pt_BR']);
    await portuguese.requested();
    await expect(htmlElement(page)).toHaveAttribute('lang', 'pt-BR');

    portuguese.release();
    await waitForAppReady(page);

    await expect(htmlElement(page)).toHaveAttribute('lang', 'pt-BR');
    await expect(layoutRoot(page)).toHaveAttribute('lang', 'pt-BR');
    expect(await storedLocale(page)).toBe('pt_BR');
  });

  test('a bg chunk that keeps failing reloads once, then fails startup visibly', async ({
    page,
    localeChunks,
  }) => {
    const states = await recordAppStates(page);
    const documents = recordDocumentRequests(page);
    const bg = await localeChunks.fail('bg');

    await page.goto('/?locale=bg', { waitUntil: 'commit' });
    await expectLocalesServed(page, ['bg']);
    await bg.requested();

    await waitOutReloads(page, documents);
    expect(
      documents,
      'exactly one recovery reload: a chunk that keeps failing must not reload the page ' +
        `again (src/utils/preloadError.ts); bg was requested ${bg.count} time(s)`
    ).toEqual(['/?locale=bg', '/?locale=bg']);
    expect(bg.count, 'one bg request per page load').toBe(2);

    // On the reloaded page: startup fails, the app never mounts, and the shell
    // says so.
    const html = htmlElement(page);
    await expect(html).toHaveAttribute('data-app-failed', 'true');
    await expect(html).not.toHaveAttribute('data-app-ready');
    await expect(page.locator('#app')).not.toHaveAttribute('data-v-app');

    // The shell's own copy (apps/web/core/templates/index.rue), which is not
    // translated.
    await expect(page.getByText("We couldn't load this page.")).toBeVisible();
    await expect(page.getByRole('link', { name: 'Reload page' })).toBeVisible();
    await expect(page.getByText('This page is taking longer than expected to load.')).toBeHidden();

    expect(
      (await states()).filter((state) => state.mounted),
      'the app never mounted, so no English stood in for Bulgarian'
    ).toEqual([]);
  });

  // A locale and its whole fallback chain load before activation (de_AT falls
  // back to de, then en), so a failed parent fails the start too.
  test('a failed parent chunk in the fallback chain fails startup', async ({
    page,
    localeChunks,
  }) => {
    const documents = recordDocumentRequests(page);
    const german = await localeChunks.fail('de');

    await page.goto('/?locale=de_AT', { waitUntil: 'commit' });
    await expectLocalesServed(page, ['de_AT', 'de']);
    await german.requested();

    await waitOutReloads(page, documents);
    expect(documents, 'exactly one recovery reload').toHaveLength(2);
    await expect(htmlElement(page)).toHaveAttribute('data-app-failed', 'true');
    await expect(htmlElement(page)).not.toHaveAttribute('data-app-ready');
    await expect(page.getByText("We couldn't load this page.")).toBeVisible();
  });
});

test.describe('switching language', () => {
  test('switching to bg keeps English until the bg chunk arrives, then switches whole', async ({
    page,
    localeChunks,
  }) => {
    const states = await recordAppStates(page);
    await page.goto('/');
    await expectLocalesServed(page, ['bg']);
    await waitForAppReady(page);
    await expect(heading(page, 'en')).toBeVisible();
    await expect(htmlElement(page)).toHaveAttribute('lang', 'en');

    const bg = await localeChunks.hold('bg');
    await chooseLanguage(page, 'bg');
    await bg.requested();

    await renderFrames(page);
    await expect(heading(page, 'en')).toBeVisible();
    await expect(layoutRoot(page)).toHaveAttribute('lang', 'en');
    await expect(htmlElement(page)).toHaveAttribute('lang', 'en');

    bg.release();
    await expect(heading(page, 'bg')).toBeVisible();
    await expect(layoutRoot(page)).toHaveAttribute('lang', 'bg');
    await expect(htmlElement(page)).toHaveAttribute('lang', 'bg');

    expect(
      mixedStates(await states()),
      'the heading never showed one language while another was active'
    ).toEqual([]);
  });

  test('a later choice wins over an earlier one that is still loading', async ({
    page,
    localeChunks,
  }) => {
    const states = await recordAppStates(page);
    const savedLocales = recordSavedLocales(page);
    await page.goto('/');
    await expectLocalesServed(page, ['bg', 'nl']);
    await waitForAppReady(page);

    const bg = await localeChunks.hold('bg');
    await chooseLanguage(page, 'bg');
    await bg.requested();

    await chooseLanguage(page, 'nl');
    await expect(heading(page, 'nl')).toBeVisible();
    await expect.poll(() => savedLocales, { message: 'the nl choice is saved' }).toEqual(['nl']);
    const nlActiveAt = await pageNow(page);

    // Let the superseded bg load finish, then give the page time to (wrongly)
    // apply it.
    const bgLoaded = page.waitForEvent('requestfinished', (request) =>
      isLocaleChunk('bg')(new URL(request.url()))
    );
    bg.release();
    await bgLoaded;
    await renderFrames(page);

    await expect(heading(page, 'nl')).toBeVisible();
    await expect(layoutRoot(page)).toHaveAttribute('lang', 'nl');
    await expect(htmlElement(page)).toHaveAttribute('lang', 'nl');
    expect(await storedLocale(page), 'the stored selection is the later choice').toBe('nl');
    expect(
      savedLocales,
      'only the winning choice is saved: a superseded switch must not save bg'
    ).toEqual(['nl']);

    const recorded = await states();
    expect(
      recorded.filter((state) => state.at >= nlActiveAt && state.copy.includes('bg')),
      'bg never rendered after nl took over'
    ).toEqual([]);
    expect(mixedStates(recorded), 'no state mixed two languages').toEqual([]);
  });

  test('a bg chunk that fails during a switch reloads once into English', async ({
    page,
    localeChunks,
  }) => {
    const documents = recordDocumentRequests(page);
    const savedLocales = recordSavedLocales(page);
    await page.goto('/');
    await expectLocalesServed(page, ['bg']);
    await waitForAppReady(page);

    const bg = await localeChunks.fail('bg');
    await chooseLanguage(page, 'bg');
    await bg.requested();

    // The failure takes the one recovery reload. Nothing on the reloaded page
    // asks for bg, so nothing fails again.
    await waitOutReloads(page, documents);
    expect(documents, 'exactly one recovery reload').toEqual(['/', '/']);
    await waitForAppReady(page);

    // The previous locale is back and nothing recorded the failed choice.
    await expect(heading(page, 'en')).toBeVisible();
    await expect(layoutRoot(page)).toHaveAttribute('lang', 'en');
    await expect(htmlElement(page)).toHaveAttribute('lang', 'en');
    // Not null: the initial navigation's activation of the preferred locale
    // writes the session selection too (languageStore.setCurrentLocale).
    expect(await storedLocale(page), 'the failed choice is not stored').not.toBe('bg');
    expect(savedLocales, 'the failed choice is not saved').toEqual([]);
    expect(bg.count, 'the reloaded page does not ask for bg').toBe(1);
  });
});
