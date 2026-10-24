// src/tests/stores/languageStore.spec.ts

import { ApplicationError } from '@/schemas';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { baseBootstrap, mockCustomer } from '../fixtures/bootstrap.fixture';
import {
  SESSION_STORAGE_KEY,
  UnsupportedLocaleError,
  useLanguageStore,
} from '@/shared/stores/languageStore';
import { globalComposer } from '@/i18n';
import type { AxiosInstance } from 'axios';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

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
    it('does not write the requesting account\'s choice onto a customer who signed in mid-request', async () => {
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
  // reject and fail the first navigation (src/router/guards.routes.ts), so
  // init() drops it from the supported locales and nothing offers or chooses
  // it. 'sw' has no generated file.
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
