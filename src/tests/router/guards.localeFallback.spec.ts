// src/tests/router/guards.localeFallback.spec.ts
//
// A locale that does not load never blocks the visitor (F22): the real route
// guards, language store, router and src/i18n.ts together. The failing locale
// is zh_Hant_TW, which the supported list names but generated/locales/ has no
// file for, so its load rejects exactly as a failed chunk does.
//
// On the initial navigation nothing is active yet, so the store activates a
// fallback: the installation's default_locale when it is supported, differs
// from the failed locale and loads, else English. A fallback is never stored
// as the session's selection. On a later navigation the active locale stays.
// Either way the failure is recorded for LocaleLoadNotice and the load error
// is logged once.

import { describe, expect, it, vi, beforeEach } from 'vitest';
import { createMemoryHistory, createRouter, type Router } from 'vue-router';

vi.mock('@/shared/stores/authStore', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/shared/stores/authStore')>()),
  useAuthStore: () => ({
    authStatus: 'anonymous',
    isAuthenticated: false,
    isFullyAuthenticated: false,
    awaitingMfa: false,
    refresh: vi.fn(),
  }),
}));

vi.mock('@/shared/composables/usePageTitle', () => ({
  usePageTitle: () => ({ setTitle: vi.fn() }),
}));

import { globalComposer } from '@/i18n';
import { setupRouterGuards } from '@/router/guards.routes';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { SESSION_STORAGE_KEY, useLanguageStore } from '@/shared/stores/languageStore';
import { setupTestPinia } from '@/tests/setup';
import { captureAppLogs } from '@/tests/utils/appLogs';

const FAILING = 'zh_Hant_TW';
const View = { render: () => null };

function makeRouter(): Router {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: View },
      { path: '/about', component: View },
    ],
  });
  setupRouterGuards(router);
  router.onError(() => undefined);
  return router;
}

async function startAt(router: Router, path: string): Promise<'ready' | Error> {
  router.push(path).catch(() => undefined);
  return router.isReady().then(
    () => 'ready' as const,
    (error: Error) => error
  );
}

describe('a locale that does not load (real guards, store and i18n)', () => {
  let setItem: ReturnType<typeof vi.spyOn>;

  beforeEach(async () => {
    await setupTestPinia({ autoInit: false });
    useBootstrapStore().update({
      supported_locales: ['en', 'nl', 'bg', FAILING, 'xx_YY'],
      cust: null,
    });
    sessionStorage.clear();
    // F7: the instance's prototype, not Storage.prototype.
    setItem = vi.spyOn(Object.getPrototypeOf(sessionStorage), 'setItem');
    // The global composer outlives each test's store.
    globalComposer.locale.value = 'en';
    document.documentElement.lang = 'en';
  });

  const store = () => useLanguageStore();
  const setDefaultLocale = (locale: string) =>
    useBootstrapStore().update({ default_locale: locale });

  describe('on the initial navigation', () => {
    it('falls back to English, records the failure and stores nothing', async () => {
      const logs = captureAppLogs();
      store().init();

      expect(await startAt(makeRouter(), `/about?locale=${FAILING}`)).toBe('ready');

      expect(store().currentLocale).toBe('en');
      expect(store().pendingLocale).toBeNull();
      expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'en' });
      expect(document.documentElement.lang).toBe('en');
      expect(setItem).not.toHaveBeenCalled();
      expect(logs.error).toHaveBeenCalledTimes(1);
    });

    it("falls back to the installation's default_locale when it is supported", async () => {
      const logs = captureAppLogs();
      setDefaultLocale('nl');
      store().init();

      expect(await startAt(makeRouter(), `/about?locale=${FAILING}`)).toBe('ready');

      expect(store().currentLocale).toBe('nl');
      expect(globalComposer.locale.value).toBe('nl');
      expect(document.documentElement.lang).toBe('nl');
      expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'nl' });
      expect(setItem).not.toHaveBeenCalled();
      expect(logs.error).toHaveBeenCalledTimes(1);
    });

    it('uses English when default_locale is the locale that failed', async () => {
      captureAppLogs();
      setDefaultLocale(FAILING);
      store().init();

      expect(await startAt(makeRouter(), `/about?locale=${FAILING}`)).toBe('ready');

      expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'en' });
    });

    it('uses English when default_locale is not supported', async () => {
      captureAppLogs();
      setDefaultLocale('ja');
      store().init();

      expect(await startAt(makeRouter(), `/about?locale=${FAILING}`)).toBe('ready');

      expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'en' });
    });

    it('uses English and logs the attempt when default_locale does not load either', async () => {
      const logs = captureAppLogs();
      setDefaultLocale('xx_YY');
      store().init();

      expect(await startAt(makeRouter(), `/about?locale=${FAILING}`)).toBe('ready');

      expect(store().currentLocale).toBe('en');
      expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'en' });
      expect(logs.error).toHaveBeenCalledTimes(2);
      expect(logs.error).toHaveBeenLastCalledWith(
        expect.objectContaining({ message: '[i18n] No messages exist for locale "xx_YY"' })
      );
    });

    it('falls back when the preferred (device) locale fails, storing nothing', async () => {
      const logs = captureAppLogs();
      store().init({ deviceLocale: 'zh-Hant-TW' });

      expect(await startAt(makeRouter(), '/about')).toBe('ready');

      expect(store().currentLocale).toBe('en');
      expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'en' });
      expect(setItem).not.toHaveBeenCalled();
      expect(logs.error).toHaveBeenCalledTimes(1);
    });
  });

  it('stores a URL locale but not the preferred one', async () => {
    store().init({ deviceLocale: 'nl' });
    const router = makeRouter();

    expect(await startAt(router, '/about')).toBe('ready');
    expect(store().currentLocale).toBe('nl');
    expect(setItem).not.toHaveBeenCalled();

    await router.push('/?locale=bg');
    expect(store().currentLocale).toBe('bg');
    expect(setItem).toHaveBeenCalledWith(SESSION_STORAGE_KEY, 'bg');
  });

  it('keeps the active locale on a later failure, and a later success clears the failure', async () => {
    const logs = captureAppLogs();
    store().init();
    const router = makeRouter();
    expect(await startAt(router, '/about?locale=nl')).toBe('ready');

    await router.push(`/?locale=${FAILING}`);

    expect(router.currentRoute.value.fullPath).toBe(`/?locale=${FAILING}`);
    expect(store().currentLocale).toBe('nl');
    expect(document.documentElement.lang).toBe('nl');
    expect(store().localeLoadFailure).toEqual({ requested: FAILING, shown: 'nl' });
    expect(logs.error).toHaveBeenCalledTimes(1);

    await router.push('/about?locale=bg');

    expect(store().currentLocale).toBe('bg');
    expect(store().localeLoadFailure).toBeNull();
  });
});
