// src/tests/stores/languageStore.spec.ts

import { ApplicationError } from '@/schemas';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { baseBootstrap, mockCustomer } from '../fixtures/bootstrap.fixture';
import {
  PREFERENCE_SAVE_TIMEOUT_MS,
  SESSION_STORAGE_KEY,
  UnsupportedLocaleError,
  useLanguageStore,
} from '@/shared/stores/languageStore';
import { globalComposer } from '@/i18n';
import { flushPromises } from '@vue/test-utils';
import type { AxiosInstance } from 'axios';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';
import { captureAppLogs } from '../utils/appLogs';
import type { ForcedPageLoadResult } from '@/utils/forcedPageLoad';
import { handlePreloadError } from '@/utils/preloadError';

// zh_Hant_TW and xx_YY stand for locales whose chunks exist but fail to load:
// the store keeps them supported, and src/i18n.ts rejects their loads because
// generated/locales/ has no file for them. Without this, init() would drop
// them like any locale this build has no messages for (loadSupportedLocales).
//
// englishFallbackFails stands for a fallback_locale.default that names another
// locale before English (['de', 'en']) whose chunk fails: an activation of
// English with its fallbacks then fails too, bundled as English is. The
// fallback map is read when src/i18n.ts loads, so it is modelled here rather
// than configured.
//
// failingChunk names a locale whose chunk fails to load in the browser's way:
// Vite's preload helper dispatches `vite:preloadError` with the error as its
// payload and then rethrows that same error, so the import rejects with the
// object the handler saw (see src/utils/preloadError.ts).
const i18nControl = vi.hoisted(() => ({
  englishFallbackFails: false,
  failingChunk: null as string | null,
}));
vi.mock('@/i18n', async (importOriginal) => {
  const FAILING_LOCALES = new Set(['zh_Hant_TW', 'xx_YY']);
  const actual = await importOriginal<typeof import('@/i18n')>();
  return {
    ...actual,
    hasLocaleMessages: (locale: string) =>
      FAILING_LOCALES.has(locale) || actual.hasLocaleMessages(locale),
    setGlobalLocale: (locale: string, options?: Parameters<typeof actual.setGlobalLocale>[1]) => {
      if (locale === 'en' && options?.fallbacks !== false && i18nControl.englishFallbackFails) {
        return Promise.reject(new Error('chunk de failed'));
      }
      if (locale === i18nControl.failingChunk) {
        const error = new Error(`chunk ${locale} failed`);
        const event = new Event('vite:preloadError', { cancelable: true });
        (event as Event & { payload: Error }).payload = error;
        window.dispatchEvent(event);
        return Promise.reject(error);
      }
      return actual.setGlobalLocale(locale, options);
    },
  };
});

describe('Language Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  beforeEach(async () => {
    // This spec drives init() itself (own options and timing), so the
    // auto-init plugin is off; see SetupTestPiniaOptions.autoInit.
    const setup = await setupTestPinia({ autoInit: false });
    axiosMock = setup.axiosMock;

    vi.useFakeTimers();

    // Mock sessionStorage
    const sessionStorageMock = {
      getItem: vi.fn(),
      setItem: vi.fn(),
      removeItem: vi.fn(),
      clear: vi.fn(),
    };

    Object.defineProperty(window, 'sessionStorage', { value: sessionStorageMock });

    // Get bootstrap store and set up supported locales
    bootstrapStore = useBootstrapStore();
    bootstrapStore.update({
      supported_locales: ['en', 'nl', 'es'],
    });
  });

  afterEach(() => {
    if (axiosMock) axiosMock?.reset();
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    bootstrapStore.$reset();
    i18nControl.englishFallbackFails = false;
    i18nControl.failingChunk = null;
  });

  // init() records options and returns the preferred locale. It activates
  // nothing: currentLocale stays null until the router's first activation,
  // and getCurrentLocale reports the preferred locale meanwhile.
  describe('Initialization', () => {
    it('initializes correctly', () => {
      const store = useLanguageStore();

      expect(store.init()).toBe('en');
      expect(store.currentLocale).toBeNull();
      expect(store.getCurrentLocale).toBe('en');
    });

    it('initializes with deviceLocale', () => {
      const store = useLanguageStore();
      expect(
        store.init({
          deviceLocale: 'en-US',
        })
      ).toBe('en');
      expect(store.currentLocale).toBeNull();
      expect(store.getCurrentLocale).toBe('en');
    });

    it('initializes with deviceLocale (es-ES)', () => {
      // Update bootstrap store with supported locales
      bootstrapStore.update({
        supported_locales: ['en', 'nl', 'es'],
      });

      // Mock sessionStorage to return null to ensure deviceLocale is used
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      const store = useLanguageStore();
      expect(
        store.init({
          deviceLocale: 'es-ES',
        })
      ).toBe('es');
      expect(store.getCurrentLocale).toBe('es');
      expect(store.currentLocale).toBeNull();
    });

    it('initializes with deviceLocale (de)', () => {
      // Update bootstrap store with supported locales including 'de'
      bootstrapStore.update({
        supported_locales: ['en', 'nl', 'es', 'de'],
      });

      // Mock sessionStorage to return null to ensure deviceLocale is used
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      const store = useLanguageStore();
      expect(
        store.init({
          deviceLocale: 'de',
        })
      ).toBe('de');
      expect(store.getCurrentLocale).toBe('de');
      expect(store.currentLocale).toBeNull();
    });

    it('initializes with stored locale', () => {
      // Update bootstrap store with supported locales
      bootstrapStore.update({
        supported_locales: ['en', 'nl', 'es'],
      });

      const sessionGetItemSpy = vi.spyOn(sessionStorage, 'getItem').mockReturnValue('nl');
      const store = useLanguageStore();
      expect(store.init()).toBe('nl');
      expect(store.getCurrentLocale).toBe('nl');
      expect(store.currentLocale).toBeNull();
      expect(sessionGetItemSpy).toBeCalled();
    });

    // N1: LanguageToggle calls init() again on mount. On the cust branch
    // that used to re-run selection and overwrite the active locale.
    it('is idempotent: a later init() changes nothing and activates nothing', async () => {
      bootstrapStore.update({ cust: { ...mockCustomer, locale: 'nl' } });
      const store = useLanguageStore();
      expect(store.init({ deviceLocale: 'es' })).toBe('nl');
      await store.setCurrentLocale('es');

      expect(store.init({ deviceLocale: 'en', storageKey: 'other.key' })).toBe('nl');

      expect(store.currentLocale).toBe('es');
      expect(store.deviceLocale).toBe('es');
      expect(store.getStorageKey).toBe(SESSION_STORAGE_KEY);
    });
  });

  describe('Language Updates', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      // Update bootstrap store with supported locales
      bootstrapStore.update({
        supported_locales: ['en', 'nl'],
      });

      store = useLanguageStore();
      store.supportedLocales = ['en', 'nl'];
    });

    afterEach(() => {
      if (store.$dispose) store.$dispose();
    });

    it('should set current locale correctly', async () => {
      // Ensure supported locales is set correctly
      store.supportedLocales = ['en', 'nl'];

      // First verify that setting 'nl' works
      await expect(store.setCurrentLocale('nl')).resolves.toBe('nl');
      expect(store.currentLocale).toBe('nl');
      expect(globalComposer.locale.value).toBe('nl');
      expect(sessionStorage.setItem).toHaveBeenCalledWith(SESSION_STORAGE_KEY, 'nl');

      // Test unsupported locale - should not change from 'nl'
      await expect(store.setCurrentLocale('invalid')).rejects.toBeInstanceOf(
        UnsupportedLocaleError
      );
      expect(store.currentLocale).toBe('nl'); // Should not change from 'nl'
      expect(sessionStorage.setItem).toHaveBeenCalledTimes(1);
    });

    // A supported locale whose messages fail to load (here: no generated
    // file) leaves the active locale and the stored selection alone.
    it('keeps the active locale and storage when the messages fail to load', async () => {
      store.supportedLocales = ['en', 'nl', 'zh_Hant_TW'];
      await store.setCurrentLocale('nl');

      await expect(store.setCurrentLocale('zh_Hant_TW')).rejects.toThrow(
        'No messages exist for locale "zh_Hant_TW"'
      );

      expect(store.currentLocale).toBe('nl');
      expect(globalComposer.locale.value).toBe('nl');
      expect(sessionStorage.setItem).toHaveBeenCalledTimes(1);
    });

    it('stores only the selection that wins when two overlap', async () => {
      store.supportedLocales = ['en', 'nl', 'es'];

      const older = store.setCurrentLocale('es');
      const newer = store.setCurrentLocale('nl');
      const [olderResult, newerResult] = await Promise.all([older, newer]);

      // The superseded call reports whatever is active when it settles (en or
      // nl, depending on which load finishes first), never its own locale.
      expect(olderResult).not.toBe('es');
      expect(newerResult).toBe('nl');
      expect(store.currentLocale).toBe('nl');
      expect(vi.mocked(sessionStorage.setItem).mock.calls).toEqual([[SESSION_STORAGE_KEY, 'nl']]);
    });

    it('should determine locale correctly', async () => {
      store.supportedLocales = ['en', 'nl'];

      // Set current locale to 'en' first so we have a baseline
      await store.setCurrentLocale('en');

      expect(store.determineLocale('nl-NL')).toBe('nl');
      expect(store.determineLocale('invalid')).toBe('en'); // Should return current locale (en)
      expect(store.determineLocale('nl')).toBe('nl');
    });

    it('should handle updateLanguage correctly', async () => {
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      await expect(store.updateLanguage('nl')).resolves.toBe('nl');
      expect(axiosMock?.history.post[0].data).toBe(JSON.stringify({ locale: 'nl' }));
      expect(store.currentLocale).toBe('nl');
    });

    // The preference is saved only once the new language is on screen. A
    // switch a newer one superseded, or one whose messages failed, sends
    // nothing: the server would otherwise hold a language the visitor does
    // not see.
    it('saves only the winning choice when two switches overlap', async () => {
      store.supportedLocales = ['en', 'nl', 'ru'];
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      const older = store.updateLanguage('ru');
      const newer = store.updateLanguage('nl');
      const [olderResult, newerResult] = await Promise.all([older, newer]);

      expect(olderResult).not.toBe('ru');
      expect(newerResult).toBe('nl');
      expect(store.currentLocale).toBe('nl');
      expect(axiosMock?.history.post.map((request) => request.data)).toEqual([
        JSON.stringify({ locale: 'nl' }),
      ]);
    });

    // Two POSTs in flight could reach the server in either order, leaving the
    // older choice saved. Each save waits for the one before it, and a save a
    // newer choice replaced while it waited is never sent.
    it('sends saves one at a time and drops a queued save a newer one replaced', async () => {
      store.supportedLocales = ['en', 'nl', 'ru'];
      let finish!: (response: [number, object]) => void;
      axiosMock?.onPost('/api/account/update-locale', { locale: 'nl' }).reply(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          })
      );
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      const first = store.updateLanguage('nl');
      await vi.waitFor(() => expect(finish).toBeTypeOf('function'));
      const second = store.updateLanguage('ru');
      await vi.waitFor(() => expect(store.currentLocale).toBe('ru'));
      await flushPromises();
      const third = store.updateLanguage('en');
      await vi.waitFor(() => expect(store.currentLocale).toBe('en'));
      await flushPromises();
      expect(axiosMock?.history.post).toHaveLength(1);

      finish([200, {}]);
      await Promise.all([first, second, third]);

      expect(axiosMock?.history.post.map((request) => request.data)).toEqual([
        JSON.stringify({ locale: 'nl' }),
        JSON.stringify({ locale: 'en' }),
      ]);
      expect(axiosMock?.history.post[0].timeout).toBe(PREFERENCE_SAVE_TIMEOUT_MS);
    });

    it('drops a queued save when another account signs in while it waits', async () => {
      store.supportedLocales = ['en', 'nl', 'ru'];
      bootstrapStore.update({ cust: { ...mockCustomer, locale: 'en' } });
      let finish!: (response: [number, object]) => void;
      axiosMock?.onPost('/api/account/update-locale', { locale: 'nl' }).reply(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          })
      );
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      const first = store.updateLanguage('nl');
      await vi.waitFor(() => expect(finish).toBeTypeOf('function'));
      const second = store.updateLanguage('ru');
      await vi.waitFor(() => expect(store.currentLocale).toBe('ru'));
      await flushPromises();
      expect(store.savingLocale).toBe('ru');

      bootstrapStore.update({
        cust: { ...mockCustomer, objid: 'cust_obj_other', extid: 'cust_ext_other', locale: 'de' },
      });
      expect(store.savingLocale).toBeNull();
      finish([200, {}]);
      await Promise.all([first, second]);

      expect(axiosMock?.history.post.map((request) => request.data)).toEqual([
        JSON.stringify({ locale: 'nl' }),
      ]);
      expect(bootstrapStore.cust?.locale).toBe('de');
    });

    it('sends a queued save once the save before it settles', async () => {
      store.supportedLocales = ['en', 'nl', 'ru'];
      let finish!: (response: [number, object]) => void;
      axiosMock?.onPost('/api/account/update-locale', { locale: 'nl' }).reply(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          })
      );
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      const first = store.updateLanguage('nl');
      await vi.waitFor(() => expect(finish).toBeTypeOf('function'));
      const second = store.updateLanguage('ru');
      await vi.waitFor(() => expect(store.currentLocale).toBe('ru'));
      await flushPromises();
      expect(axiosMock?.history.post).toHaveLength(1);

      finish([500, {}]);
      await expect(second).resolves.toBe('ru');
      await first.catch(() => undefined);

      expect(axiosMock?.history.post.map((request) => request.data)).toEqual([
        JSON.stringify({ locale: 'nl' }),
        JSON.stringify({ locale: 'ru' }),
      ]);
      expect(store.localeSaveFailure).toBeNull();
    });

    it('saves nothing when the messages fail to load', async () => {
      store.supportedLocales = ['en', 'nl', 'zh_Hant_TW'];
      bootstrapStore.update({ cust: { ...mockCustomer, locale: 'en' } });
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      await expect(store.updateLanguage('zh_Hant_TW')).rejects.toThrow(
        'No messages exist for locale "zh_Hant_TW"'
      );

      expect(axiosMock?.history.post).toHaveLength(0);
      expect(bootstrapStore.cust?.locale).toBe('en');
    });

    // The auth route guard re-applies bootstrapStore.cust.locale on every
    // protected navigation. If updateLanguage leaves the snapshot stale, the
    // next page change silently reverts the choice the user just made.
    it('keeps the bootstrap snapshot locale in step with the saved preference', async () => {
      bootstrapStore.update({ cust: { ...mockCustomer, locale: 'en' } });
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      await store.updateLanguage('nl');

      expect(bootstrapStore.cust?.locale).toBe('nl');
    });

    // If an auth refresh swaps the account while the preference request is in
    // flight, the patch must not land on the account that signed in afterwards.
    it("does not write the requesting account's choice onto a customer who signed in mid-request", async () => {
      bootstrapStore.update({ cust: { ...mockCustomer, locale: 'en' } });
      axiosMock?.onPost('/api/account/update-locale').reply(() => {
        bootstrapStore.update({
          cust: { ...mockCustomer, objid: 'cust_obj_other', extid: 'cust_ext_other', locale: 'de' },
        });
        return [200, {}];
      });

      await store.updateLanguage('nl');

      expect(bootstrapStore.cust?.extid).toBe('cust_ext_other');
      expect(bootstrapStore.cust?.locale).toBe('de');
    });

    it('does not invent a customer when the visitor is anonymous', async () => {
      bootstrapStore.update({ cust: null });
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      await store.updateLanguage('nl');

      expect(bootstrapStore.cust).toBeNull();
    });

    describe('Error Handling', () => {
      it.skip('server should not allow two-part locales updateLanguage', async () => {
        const locale = 'en-US';

        // Setup axiosMock with 404 response
        axiosMock?.onPost('/api/account/update-locale', { locale }).reply(400); // TODO: Not correct

        let caughtError: ApplicationError;
        try {
          await store.updateLanguage(locale);
          throw new Error('Failed testcase: expected error not thrown');
        } catch (err) {
          caughtError = err as ApplicationError;
        }

        // // Verify specific error properties
        expect(caughtError).toBeDefined();
        expect(caughtError.type).toBe('technical');
        expect(caughtError.severity).toBe('error');

        // Verify API was called with correct parameters
        expect(axiosMock?.history.post).toHaveLength(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/account/update-locale');
        expect(JSON.parse(axiosMock?.history.post[0].data)).toEqual({ locale });
      });

      it('should handle network errors in updateLanguage', async () => {
        const locale = 'nl';

        // Setup axiosMock
        axiosMock?.onPost('/api/account/update-locale', { locale }).networkError();

        // Expect raw AxiosError, not ApplicationError
        await expect(store.updateLanguage(locale)).rejects.toThrow();

        // Verify API was called with correct parameters
        expect(axiosMock?.history.post).toHaveLength(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/account/update-locale');
        expect(JSON.parse(axiosMock?.history.post[0].data)).toEqual({ locale });
      });

      it('should handle server errors in updateLanguage', async () => {
        const locale = 'nl';

        // Setup axiosMock with 500 response
        axiosMock
          ?.onPost('/api/account/update-locale', { locale })
          .reply(500, { message: 'Internal Server Error' });

        // Expect raw AxiosError, not ApplicationError
        await expect(store.updateLanguage(locale)).rejects.toThrow();

        // Verify API was called correctly
        expect(axiosMock?.history.post).toHaveLength(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/account/update-locale');
        expect(JSON.parse(axiosMock?.history.post[0].data)).toEqual({ locale });
      });

      it('should handle invalid locale validation', async () => {
        const locale = 'invalid!';

        // Expect validation error, not ApplicationError
        await expect(store.updateLanguage(locale)).rejects.toThrow();

        // Verify no API call was made
        expect(axiosMock?.history.post).toHaveLength(0);
      });
    });
  });

  describe('Locale Normalization', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      // Update bootstrap store with locales that include region variants
      bootstrapStore.update({
        supported_locales: ['en', 'it_IT', 'fr_FR', 'fr_CA', 'de', 'de_AT'],
      });

      store = useLanguageStore();
      store.supportedLocales = ['en', 'it_IT', 'fr_FR', 'fr_CA', 'de', 'de_AT'];
    });

    it('should handle exact match with underscores (it_IT)', async () => {
      await store.setCurrentLocale('it_IT');
      expect(store.currentLocale).toBe('it_IT');
    });

    it('should handle case-insensitive exact match (IT_IT -> it_IT)', async () => {
      await store.setCurrentLocale('IT_IT');
      expect(store.currentLocale).toBe('it_IT');
    });

    it('should normalize hyphen to underscore (it-IT -> it_IT)', async () => {
      await store.setCurrentLocale('it-IT');
      expect(store.currentLocale).toBe('it_IT');
    });

    it('should handle simple locale (en)', async () => {
      await store.setCurrentLocale('en');
      expect(store.currentLocale).toBe('en');
    });

    it('should handle exact match with different case (fr-ca -> fr_CA)', async () => {
      await store.setCurrentLocale('fr-ca');
      expect(store.currentLocale).toBe('fr_CA');
    });

    it('should fallback to primary language match (de-CH -> de)', async () => {
      // de-CH not in list, but 'de' is, so should match to 'de'
      await store.setCurrentLocale('de-CH');
      expect(store.currentLocale).toBe('de');
    });

    it('should prefer exact match over primary match when both exist (fr_CA)', async () => {
      // Both fr_CA and fr_FR exist, fr_CA should match exactly
      await store.setCurrentLocale('fr_CA');
      expect(store.currentLocale).toBe('fr_CA');
    });

    it('should handle updateLanguage with region locales', async () => {
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      await store.updateLanguage('it_IT');
      expect(axiosMock?.history.post[0].data).toBe(JSON.stringify({ locale: 'it_IT' }));
    });

    it('should handle updateLanguage with hyphenated input (it-IT -> it_IT)', async () => {
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});

      await store.updateLanguage('it-IT');
      // Should normalize to it_IT before sending to server
      expect(axiosMock?.history.post[0].data).toBe(JSON.stringify({ locale: 'it_IT' }));
    });

    it('should reject unsupported locale', async () => {
      // 'ja' not in supportedLocales
      await expect(store.updateLanguage('ja')).rejects.toThrow('Unsupported locale: ja');
      await expect(store.updateLanguage('ja')).rejects.toBeInstanceOf(UnsupportedLocaleError);
      expect(axiosMock?.history.post).toHaveLength(0);
    });

    // #4284: tags longer than xx-XX are valid BCP 47 and must fall back to
    // the primary language instead of failing schema validation.
    // Matching only: no generated file exists for zh_Hant_TW, so the
    // matched locale is checked with resolveSupportedLocale, which loads
    // nothing.
    it('should exact-match multi-hyphen tags against supported locales (zh-Hant-TW -> zh_Hant_TW)', () => {
      // All hyphens must normalize for comparison, not just the first one.
      store.supportedLocales = ['en', 'zh_Hant_TW'];
      expect(store.resolveSupportedLocale('zh-Hant-TW')).toBe('zh_Hant_TW');
    });

    it('should fall back to primary language for script subtags (it-Latn-IT -> it_IT)', async () => {
      await store.setCurrentLocale('it-Latn-IT');
      expect(store.currentLocale).toBe('it_IT');
    });

    it('should fall back to primary language for variant subtags (en-US-POSIX -> en)', async () => {
      await store.setCurrentLocale('en-US-POSIX');
      expect(store.currentLocale).toBe('en');
    });

    it('resolves no locale for one that matches nothing', () => {
      expect(store.resolveSupportedLocale('ja')).toBeNull();
      expect(store.resolveSupportedLocale('xx-YY')).toBeNull();
    });

    it('should initialize with default locale when deviceLocale is garbage', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      const freshStore = useLanguageStore();
      freshStore.$reset();
      const result = freshStore.init({ deviceLocale: '!!not-a-locale!!' });
      expect(result).toBe('en');
    });
  });

  // Store a locale as the session's selection only when the visitor or the
  // account chose it; one the app picked must not outrank a domain locale that
  // changes later in the session.
  describe('Remembering the selection', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      store = useLanguageStore();
      store.supportedLocales = ['en', 'nl'];
    });

    it('stores the locale by default', async () => {
      await store.setCurrentLocale('nl');

      expect(sessionStorage.setItem).toHaveBeenCalledWith(SESSION_STORAGE_KEY, 'nl');
    });

    it('activates without storing when told not to remember', async () => {
      await expect(store.setCurrentLocale('nl', { remember: false })).resolves.toBe('nl');

      expect(store.currentLocale).toBe('nl');
      expect(globalComposer.locale.value).toBe('nl');
      expect(sessionStorage.setItem).not.toHaveBeenCalled();
    });
  });

  // pendingLocale is the latest choice while it loads; LanguageToggle uses it
  // so that picking the active language again supersedes a pending switch.
  describe('pendingLocale', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      store = useLanguageStore();
      store.supportedLocales = ['en', 'nl', 'es', 'zh_Hant_TW'];
    });

    it('names the locale while it loads and clears once it is active', async () => {
      expect(store.pendingLocale).toBeNull();

      const switching = store.setCurrentLocale('nl');
      expect(store.pendingLocale).toBe('nl');
      await switching;

      expect(store.pendingLocale).toBeNull();
    });

    it('is cleared only by the latest call', async () => {
      // en needs no load and settles first while the newer call still loads.
      // tr is used nowhere else in this file, so the global composer (which
      // outlives each test's store) has not loaded it yet.
      store.supportedLocales = ['en', 'tr'];
      const older = store.setCurrentLocale('en');
      const newer = store.setCurrentLocale('tr');
      expect(store.pendingLocale).toBe('tr');

      await older;
      expect(store.pendingLocale).toBe('tr');

      await newer;
      expect(store.pendingLocale).toBeNull();
      expect(store.currentLocale).toBe('tr');
    });

    it('clears when the load fails', async () => {
      await expect(store.setCurrentLocale('zh_Hant_TW')).rejects.toThrow();

      expect(store.pendingLocale).toBeNull();
    });

    // F20: picking the active language while another one loads is a new
    // choice. The pending switch neither activates nor saves its locale.
    it('lets a switch back to the active locale supersede a pending one', async () => {
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});
      store.supportedLocales = ['en', 'nl', 'ru'];
      await store.setCurrentLocale('en');

      const away = store.updateLanguage('ru');
      expect(store.pendingLocale).toBe('ru');
      const back = store.updateLanguage('en');
      expect(store.pendingLocale).toBe('en');

      expect(await Promise.all([away, back])).toEqual(['en', 'en']);
      expect(store.currentLocale).toBe('en');
      expect(store.pendingLocale).toBeNull();
      expect(axiosMock?.history.post.map((request) => request.data)).toEqual([
        JSON.stringify({ locale: 'en' }),
      ]);
    });
  });

  // F22: a locale whose messages do not load never blocks the visitor. The
  // store settles the locale shown and records the failure for
  // LocaleLoadNotice. zh_Hant_TW is supported here and its load rejects as a
  // failed chunk does (see the @/i18n mock above).
  describe('Locale load failures', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      bootstrapStore.update({ supported_locales: ['en', 'nl', 'es', 'zh_Hant_TW', 'xx_YY'] });
      store = useLanguageStore();
      store.init();
    });

    it('keeps the active locale and records the failure', async () => {
      await store.setCurrentLocale('nl');
      vi.mocked(sessionStorage.setItem).mockClear();

      await expect(store.recoverFromLocaleLoadFailure('zh_Hant_TW')).resolves.toBe('nl');

      expect(store.currentLocale).toBe('nl');
      expect(store.localeLoadFailure).toEqual({ requested: 'zh_Hant_TW', shown: 'nl' });
      expect(sessionStorage.setItem).not.toHaveBeenCalled();
    });

    it('records the requested locale normalized, or as given when unsupported', async () => {
      await store.setCurrentLocale('nl');

      await store.recoverFromLocaleLoadFailure('ZH-hant-tw');
      expect(store.localeLoadFailure?.requested).toBe('zh_Hant_TW');

      await store.recoverFromLocaleLoadFailure('sw');
      expect(store.localeLoadFailure?.requested).toBe('sw');
    });

    describe('before any locale is active', () => {
      it("activates the installation's default_locale, without storing it", async () => {
        bootstrapStore.update({ default_locale: 'nl' });

        await expect(store.recoverFromLocaleLoadFailure('zh_Hant_TW')).resolves.toBe('nl');

        expect(store.currentLocale).toBe('nl');
        expect(globalComposer.locale.value).toBe('nl');
        expect(store.localeLoadFailure).toEqual({ requested: 'zh_Hant_TW', shown: 'nl' });
        expect(sessionStorage.setItem).not.toHaveBeenCalled();
      });

      it.each([
        ['the locale that failed', 'zh_Hant_TW'],
        ['not supported', 'ja'],
        ['English already', 'en'],
      ])('activates English when default_locale is %s', async (_label, defaultLocale) => {
        bootstrapStore.update({ default_locale: defaultLocale });

        await expect(store.recoverFromLocaleLoadFailure('zh_Hant_TW')).resolves.toBe('en');

        expect(store.currentLocale).toBe('en');
        expect(store.localeLoadFailure).toEqual({ requested: 'zh_Hant_TW', shown: 'en' });
        expect(sessionStorage.setItem).not.toHaveBeenCalled();
      });

      // The chunk that failed may be the one configured behind English. The
      // last resort loads English alone, so it opens whatever else failed.
      it('activates English without its fallbacks when the chunk behind it fails', async () => {
        bootstrapStore.update({ default_locale: 'en' });
        i18nControl.englishFallbackFails = true;

        await expect(store.recoverFromLocaleLoadFailure('zh_Hant_TW')).resolves.toBe('en');

        expect(store.currentLocale).toBe('en');
        expect(globalComposer.locale.value).toBe('en');
        expect(store.localeLoadFailure).toEqual({ requested: 'zh_Hant_TW', shown: 'en' });
        // Ordinary activations stay strict: English with its chain still fails.
        await expect(store.setCurrentLocale('en')).rejects.toThrow('chunk de failed');
      });

      it('activates English and logs it when default_locale does not load either', async () => {
        const logs = captureAppLogs();
        bootstrapStore.update({ default_locale: 'xx_YY' });

        await expect(store.recoverFromLocaleLoadFailure('zh_Hant_TW')).resolves.toBe('en');

        expect(store.localeLoadFailure).toEqual({ requested: 'zh_Hant_TW', shown: 'en' });
        expect(logs.error).toHaveBeenCalledTimes(1);
        expect(logs.error).toHaveBeenCalledWith(
          expect.objectContaining({ message: '[i18n] No messages exist for locale "xx_YY"' })
        );
      });
    });

    it('clears the failure on the next successful activation', async () => {
      await store.setCurrentLocale('nl');
      await store.recoverFromLocaleLoadFailure('zh_Hant_TW');

      await store.setCurrentLocale('es', { remember: false });

      expect(store.localeLoadFailure).toBeNull();
    });

    it('clears the failure on dismissal and keeps the locale', async () => {
      await store.setCurrentLocale('nl');
      await store.recoverFromLocaleLoadFailure('zh_Hant_TW');

      store.dismissLocaleLoadFailure();

      expect(store.localeLoadFailure).toBeNull();
      expect(store.currentLocale).toBe('nl');
    });

    // The language toggle path: the failed switch is recorded before its load
    // error reaches the caller, and nothing is saved.
    it('updateLanguage records a failed load, keeps the locale and rethrows', async () => {
      axiosMock?.onPost('/api/account/update-locale').reply(200, {});
      await store.setCurrentLocale('nl');

      await expect(store.updateLanguage('zh_Hant_TW')).rejects.toThrow(
        'No messages exist for locale "zh_Hant_TW"'
      );

      expect(store.currentLocale).toBe('nl');
      expect(store.localeLoadFailure).toEqual({ requested: 'zh_Hant_TW', shown: 'nl' });
      expect(axiosMock?.history.post).toHaveLength(0);
    });

    it('updateLanguage records nothing for an unsupported locale', async () => {
      await expect(store.updateLanguage('ja')).rejects.toBeInstanceOf(UnsupportedLocaleError);

      expect(store.localeLoadFailure).toBeNull();
    });

    it('$reset clears the pending locale and the failure', async () => {
      await store.setCurrentLocale('nl');
      await store.recoverFromLocaleLoadFailure('zh_Hant_TW');
      const switching = store.setCurrentLocale('es');
      expect(store.pendingLocale).toBe('es');

      store.$reset();

      expect(store.pendingLocale).toBeNull();
      expect(store.localeLoadFailure).toBeNull();
      expect(store.currentLocale).toBeNull();
      // Let the switch settle inside this test.
      await switching;
    });
  });

  // F24: a locale chunk is a chunk like any other. One that fails to load
  // reloads the page under the ADR-046 bound (the deployment-skew recovery),
  // before anything is shown and on a later switch alike. A locale the
  // visitor chose is stored before that reload, so the reloaded page asks for
  // it again instead of opening in the language shown before. When the bound
  // refuses the reload, the switch fails in place: the active locale stays,
  // nothing is stored, and the failure is recorded for LocaleLoadNotice. Each
  // "chunk" here fails as a browser's would (see failingChunk); the real
  // handler decides.
  describe('A failed chunk and the forced reload (F24)', () => {
    const results: ForcedPageLoadResult[] = [];
    const reload = vi.fn();
    // The ADR-046 marker: null allows a reload, a fresh timestamp refuses it.
    let marker: string | null = null;
    const storage = { getItem: () => marker, setItem: vi.fn() };
    const onPreloadError = (event: Event) =>
      results.push(handlePreloadError(event, { now: Date.now(), reload, storage }));
    let store: ReturnType<typeof useLanguageStore>;

    const storedSelections = () =>
      vi.mocked(sessionStorage.setItem).mock.calls.filter(([key]) => key === SESSION_STORAGE_KEY);

    function failChunk(code: string) {
      i18nControl.failingChunk = code;
    }

    beforeEach(() => {
      results.length = 0;
      reload.mockReset();
      marker = null;
      window.addEventListener('vite:preloadError', onPreloadError);
      store = useLanguageStore();
      store.supportedLocales = ['en', 'nl', 'ko', 'pl', 'hu'];
    });

    afterEach(() => {
      window.removeEventListener('vite:preloadError', onPreloadError);
    });

    it('lets the first activation reload the page, with the choice stored for it', async () => {
      failChunk('ko');

      await expect(store.setCurrentLocale('ko')).rejects.toThrow('chunk ko failed');

      expect(results).toEqual(['reloading']);
      expect(reload).toHaveBeenCalledTimes(1);
      expect(store.currentLocale).toBeNull();
      expect(storedSelections()).toEqual([[SESSION_STORAGE_KEY, 'ko']]);
    });

    it('lets a later switch reload the page too, with the active locale unchanged and the choice stored', async () => {
      await store.setCurrentLocale('nl');
      failChunk('pl');

      await expect(store.setCurrentLocale('pl')).rejects.toThrow('chunk pl failed');

      expect(results).toEqual(['reloading']);
      expect(reload).toHaveBeenCalledTimes(1);
      expect(store.currentLocale).toBe('nl');
      expect(storedSelections()).toEqual([
        [SESSION_STORAGE_KEY, 'nl'],
        [SESSION_STORAGE_KEY, 'pl'],
      ]);
    });

    // The guard activates the preferred locale and the store its fallbacks
    // with remember false: a language the app picked is not the visitor's
    // choice, and the reloaded page picks again.
    it('stores nothing for a locale the app chose, though the page reloads for it', async () => {
      failChunk('ko');

      await expect(store.setCurrentLocale('ko', { remember: false })).rejects.toThrow();

      expect(results).toEqual(['reloading']);
      expect(reload).toHaveBeenCalledTimes(1);
      expect(storedSelections()).toEqual([]);
    });

    it('keeps the locale and records the failure when the bound refuses the reload', async () => {
      const logs = captureAppLogs();
      await store.setCurrentLocale('nl');
      marker = String(Date.now());
      failChunk('hu');

      await expect(store.updateLanguage('hu')).rejects.toThrow('chunk hu failed');

      expect(results).toEqual(['bounded']);
      expect(reload).not.toHaveBeenCalled();
      expect(store.currentLocale).toBe('nl');
      expect(store.localeLoadFailure).toEqual({ requested: 'hu', shown: 'nl' });
      expect(storedSelections(), 'no reload, so the choice is not stored').toEqual([
        [SESSION_STORAGE_KEY, 'nl'],
      ]);
      // A chunk failing with the reload already spent is the page's error.
      expect(logs.error).toHaveBeenCalledTimes(1);
    });
  });

  describe('Language Headers', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      // Update bootstrap store with supported locales
      bootstrapStore.update({
        supported_locales: ['en', 'nl', 'es'],
      });

      store = useLanguageStore();
      store.init();
    });

    it('should return array of unique languages', async () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('uk-UA');
      await store.setCurrentLocale('en');
      expect(store.acceptLanguages).toEqual(['en', 'uk-UA']); // Should include navigator.language

      await store.setCurrentLocale('nl');
      expect(store.acceptLanguages).toEqual(['nl', 'uk-UA']);
    });

    // Requests made during the initial navigation, before any activation,
    // already ask for the locale about to be activated.
    it('leads with the preferred locale before the first activation', () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('uk-UA');
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('es');

      expect(store.currentLocale).toBeNull();
      expect(store.acceptLanguageHeader).toBe('es,uk-UA');
    });

    it('should handle matching browser and selected languages', async () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('nl');
      await store.setCurrentLocale('nl');
      expect(store.acceptLanguages).toEqual(['nl']);
    });

    it('should format header string correctly', async () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('uk-UA');
      await store.setCurrentLocale('nl');
      expect(store.acceptLanguageHeader).toBe('nl,uk-UA');
    });

    it('should maintain selected language as primary', async () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('de-DE');
      await store.setCurrentLocale('es');
      const languages = store.acceptLanguages;
      expect(languages[0]).toBe('es');
      expect(languages).toContain('de-DE');
    });
  });

  // A locale the server lists without a generated messages file: a pruned
  // build, a locales sync that did not run, a custom locale list. The server
  // keeps it in supported_locales (lib/onetime/initializers/load_locales.rb
  // logs the missing file and goes on to the next). Activating it would
  // always reject and show the visitor a fallback with LocaleLoadNotice
  // (src/router/guards.routes.ts), so init() drops it from the supported
  // locales and nothing offers or chooses it. 'sw' has no generated file.
  describe('a supported locale this build has no messages for', () => {
    beforeEach(() => {
      bootstrapStore.update({ supported_locales: ['en', 'sw', 'nl'], default_locale: 'sw' });
    });

    it('is dropped from the supported locales at init', () => {
      const store = useLanguageStore();
      store.init();

      expect(store.getSupportedLocales).toEqual(['en', 'nl']);
    });

    it('is passed over at every rank of the preference hierarchy', () => {
      bootstrapStore.update({
        cust: { ...mockCustomer, locale: 'sw' },
        domain_branding: {
          ...(baseBootstrap.domain_branding as NonNullable<BootstrapPayload['domain_branding']>),
          locale: 'sw',
        },
      });
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('sw');

      const store = useLanguageStore();
      // Account, stored, brand, device and default_locale all name it; the
      // bundled DEFAULT_LOCALE is what is left.
      expect(store.init({ deviceLocale: 'sw' })).toBe('en');
    });

    it('yields to the next candidate that has messages', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('sw');

      const store = useLanguageStore();
      expect(store.init({ deviceLocale: 'nl' })).toBe('nl');
    });

    it('resolves to nothing, so a URL naming it is ignored like an unsupported one', async () => {
      const store = useLanguageStore();
      store.init();

      expect(store.resolveSupportedLocale('sw')).toBeNull();
      await expect(store.setCurrentLocale('sw')).rejects.toBeInstanceOf(UnsupportedLocaleError);
      expect(store.currentLocale).toBeNull();
    });
  });
});
