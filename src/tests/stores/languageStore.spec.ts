// src/tests/stores/languageStore.spec.ts
import { ApplicationError } from '@/schemas';
import { SESSION_STORAGE_KEY, useLanguageStore } from '@/stores/languageStore';
import { setupTestPinia } from '../setup';
import { WindowService } from '@/services/window.service';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';

// vi.spyOn(WindowService, 'getState').mockImplementation(
//   () =>
//     ({
//       authenticated: true,
//       locale: 'en',
//     }) as any
// );

describe('Language Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;

    vi.useFakeTimers();

    // Mock sessionStorage
    const sessionStorageMock = {
      getItem: vi.fn(),
      setItem: vi.fn(),
      clear: vi.fn(),
    };

    Object.defineProperty(window, 'sessionStorage', { value: sessionStorageMock });

    // Mock window.supported_locales
    vi.stubGlobal('supported_locales', ['en', 'fr', 'es']);
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  describe('Initialization', () => {
    it('initializes correctly', () => {
      const store = useLanguageStore();

      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr', 'es'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      store.init();
      expect(store.currentLocale).toBe('en'); // Should be 'en' after init, not null
      expect(store.getCurrentLocale).toBe('en');
    });

    it('initializes with deviceLocale', () => {
      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr', 'es'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      const store = useLanguageStore();
      store.init({
        deviceLocale: 'en-US',
      });
      expect(store.currentLocale).toBe('en');
      expect(store.getCurrentLocale).toBe('en');
    });

    it('initializes with deviceLocale (es-ES)', () => {
      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr', 'es'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      // Mock sessionStorage to return null to ensure deviceLocale is used
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      const store = useLanguageStore();
      store.init({
        deviceLocale: 'es-ES',
      });
      expect(store.currentLocale).toBe('es');
    });

    it('initializes with deviceLocale (de)', () => {
      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr', 'es', 'de'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      // Mock sessionStorage to return null to ensure deviceLocale is used
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      const store = useLanguageStore();
      store.init({
        deviceLocale: 'de',
      });
      expect(store.currentLocale).toBe('de');
    });

    it('initializes with stored locale', () => {
      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr', 'es'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      const sessionGetItemSpy = vi.spyOn(sessionStorage, 'getItem').mockReturnValueOnce('fr');
      const store = useLanguageStore();
      store.init();
      expect(store.currentLocale).toBe('fr');
      expect(sessionGetItemSpy).toBeCalled();
    });
  });

  describe('Language Updates', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      store = useLanguageStore();
      store.supportedLocales = ['en', 'fr'];
    });

    afterEach(() => {
      if (store.$dispose) store.$dispose();
    });

    it('should set current locale correctly', () => {
      // Ensure supported locales is set correctly
      store.supportedLocales = ['en', 'fr'];

      // First verify that setting 'fr' works
      store.setCurrentLocale('fr');
      expect(store.currentLocale).toBe('fr');
      expect(sessionStorage.setItem).toHaveBeenCalledWith(SESSION_STORAGE_KEY, 'fr');

      // Test unsupported locale - should not change from 'fr'
      const consoleSpy = vi.spyOn(console, 'warn');
      store.setCurrentLocale('invalid');
      expect(store.currentLocale).toBe('fr'); // Should not change from 'fr'
      expect(consoleSpy).toHaveBeenCalled();
    });

    it('should determine locale correctly', () => {
      store.supportedLocales = ['en', 'fr'];

      // Set current locale to 'en' first so we have a baseline
      store.setCurrentLocale('en');

      expect(store.determineLocale('fr-FR')).toBe('fr');
      expect(store.determineLocale('invalid')).toBe('en'); // Should return current locale (en)
      expect(store.determineLocale('fr')).toBe('fr');
    });

    it('should handle updateLanguage correctly', async () => {
      axiosMock.onPost('/api/v2/account/update-locale').reply(200, {});

      await store.updateLanguage('fr');
      expect(axiosMock.history.post[0].data).toBe(JSON.stringify({ locale: 'fr' }));
    });

    describe('Error Handling', () => {
      it.skip('server should not allow two-part locales updateLanguage', async () => {
        const locale = 'en-US';

        // Setup axiosMock with 404 response
        axiosMock.onPost('/api/v2/account/update-locale', { locale }).reply(400); // TODO: Not correct

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
        expect(axiosMock.history.post).toHaveLength(1);
        expect(axiosMock.history.post[0].url).toBe('/api/v2/account/update-locale');
        expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({ locale });
      });

      it('should handle network errors in updateLanguage', async () => {
        const locale = 'fr';

        // Setup axiosMock
        axiosMock.onPost('/api/v2/account/update-locale', { locale }).networkError();

        // Expect raw AxiosError, not ApplicationError
        await expect(store.updateLanguage(locale)).rejects.toThrow();

        // Verify API was called with correct parameters
        expect(axiosMock.history.post).toHaveLength(1);
        expect(axiosMock.history.post[0].url).toBe('/api/v2/account/update-locale');
        expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({ locale });
      });

      it('should handle server errors in updateLanguage', async () => {
        const locale = 'fr';

        // Setup axiosMock with 500 response
        axiosMock
          .onPost('/api/v2/account/update-locale', { locale })
          .reply(500, { message: 'Internal Server Error' });

        // Expect raw AxiosError, not ApplicationError
        await expect(store.updateLanguage(locale)).rejects.toThrow();

        // Verify API was called correctly
        expect(axiosMock.history.post).toHaveLength(1);
        expect(axiosMock.history.post[0].url).toBe('/api/v2/account/update-locale');
        expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({ locale });
      });

      it('should handle invalid locale validation', async () => {
        const locale = 'invalid!';

        // Expect validation error, not ApplicationError
        await expect(store.updateLanguage(locale)).rejects.toThrow();

        // Verify no API call was made
        expect(axiosMock.history.post).toHaveLength(0);
      });
    });
  });

  describe('Language Headers', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      // Mock WindowService.get to return supported locales
      vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
        if (key === 'supported_locales') return ['en', 'fr', 'es'];
        if (key === 'cust') return undefined;
        return undefined;
      });

      store = useLanguageStore();
      store.init();
    });

    it('should return array of unique languages', () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('uk-UA');
      store.setCurrentLocale('en');
      expect(store.acceptLanguages).toEqual(['en', 'uk-UA']); // Should include navigator.language

      store.setCurrentLocale('fr');
      expect(store.acceptLanguages).toEqual(['fr', 'uk-UA']);
    });

    it('should handle matching browser and selected languages', () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('fr');
      store.setCurrentLocale('fr');
      expect(store.acceptLanguages).toEqual(['fr']);
    });

    it('should format header string correctly', () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('uk-UA');
      store.setCurrentLocale('fr');
      expect(store.acceptLanguageHeader).toBe('fr,uk-UA');
    });

    it('should maintain selected language as primary', () => {
      vi.spyOn(navigator, 'language', 'get').mockReturnValue('de-DE');
      store.setCurrentLocale('es');
      const languages = store.acceptLanguages;
      expect(languages[0]).toBe('es');
      expect(languages).toContain('de-DE');
    });
  });
});
