// src/stores/languageStore.spec.ts
import { ApplicationError } from '@/schemas';
import { SESSION_STORAGE_KEY, useLanguageStore } from '@/stores/languageStore';
import { createApi } from '@/api';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('Language Store', () => {
  beforeEach(() => {
    // creates a fresh pinia and makes it active
    // so it's automatically picked up by any useStore() call
    // without having to pass it to it: `useStore(pinia)`
    setActivePinia(createPinia());
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
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  describe('Initialization', () => {
    it('initializes correctly', () => {
      const store = useLanguageStore();
      store.init();
      expect(store.currentLocale).toBeNull();
      expect(store.getCurrentLocale).toBe('en');
    });

    it('initializes with deviceLocale', () => {
      const store = useLanguageStore();
      store.init(undefined, {
        deviceLocale: 'en-US',
      });
      expect(store.currentLocale).toBe('en');
      expect(store.getCurrentLocale).toBe('en');
    });

    it('initializes with deviceLocale (es-ES)', () => {
      const store = useLanguageStore();
      store.init(undefined, {
        deviceLocale: 'es-ES',
      });
      const setupAsyncHandlerSpy = vi.spyOn(sessionStorage, 'getItem').mockReturnValueOnce(null);
      expect(store.currentLocale).toBe('es');
      // expect(setupAsyncHandlerSpy).toBeCalledTimes(0);
    });

    it('initializes with deviceLocale (de)', () => {
      const store = useLanguageStore();
      store.init(undefined, {
        deviceLocale: 'de',
      });
      expect(store.currentLocale).toBe('de');
    });

    it('initializes with stored locale', () => {
      const setupAsyncHandlerSpy = vi.spyOn(sessionStorage, 'getItem').mockReturnValueOnce('fr');
      const store = useLanguageStore();
      store.init();
      expect(store.currentLocale).toBe('fr');
      expect(setupAsyncHandlerSpy).toBeCalled();
    });
  });

  describe('Language Updates', () => {
    let axiosMock: AxiosMockAdapter;
    let axiosInstance: ReturnType<typeof createApi>;
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      axiosInstance = createApi();
      axiosMock = new AxiosMockAdapter(axiosInstance);
      store = useLanguageStore();
      store.setupAsyncHandler(axiosInstance);
      store.supportedLocales = ['en', 'fr'];
    });

    afterEach(() => {
      store.$dispose();
      axiosMock.reset();
    });

    it('should set current locale correctly', () => {
      store.supportedLocales = ['en', 'fr'];

      store.setCurrentLocale('fr');
      expect(store.currentLocale).toBe('fr');
      expect(sessionStorage.setItem).toHaveBeenCalledWith(SESSION_STORAGE_KEY, 'fr');

      // Test unsupported locale
      const consoleSpy = vi.spyOn(console, 'warn');
      store.setCurrentLocale('invalid');
      expect(store.currentLocale).toBe('fr'); // Should not change
      expect(consoleSpy).toHaveBeenCalled();
    });

    it('should determine locale correctly', () => {
      store.supportedLocales = ['en', 'fr'];

      expect(store.determineLocale('fr-FR')).toBe('fr');
      expect(store.determineLocale('invalid')).toBe('en'); // Default
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

        let caughtError: ApplicationError;
        try {
          await store.updateLanguage(locale);
          throw new Error('Failed testcase: expected error not thrown');
        } catch (err) {
          caughtError = err as ApplicationError;
          // console.log(caughtError);
        }

        // Verify specific error properties
        expect(caughtError).toBeDefined();
        expect(caughtError.type).toBe('technical');
        expect(caughtError.severity).toBe('error');

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

        let caughtError: ApplicationError;
        try {
          await store.updateLanguage(locale);
          throw new Error('Failed testcase: expected error not thrown');
        } catch (err) {
          caughtError = err as ApplicationError;
          // console.log(caughtError);
        }

        // Verify specific error properties
        expect(caughtError).toBeDefined();
        expect(caughtError.type).toBe('technical');
        expect(caughtError.severity).toBe('error');

        // Verify API was called correctly
        expect(axiosMock.history.post).toHaveLength(1);
        expect(axiosMock.history.post[0].url).toBe('/api/v2/account/update-locale');
        expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({ locale });
      });

      it('should handle invalid locale validation', async () => {
        const locale = 'invalid!';

        let caughtError: ApplicationError;

        try {
          await store.updateLanguage(locale);
          throw new Error('Failed testcase: expected error not thrown');
        } catch (err) {
          caughtError = err as ApplicationError;
        }

        // Verify no API call was made
        expect(axiosMock.history.post).toHaveLength(0);

        // Verify specific error properties
        expect(caughtError).toBeDefined();
        expect(caughtError.type).toBe('technical');
        expect(caughtError.severity).toBe('error');

        // Verify the error contains validation details
        const errorData = JSON.parse(caughtError.message);
        expect(errorData).toMatchObject([{ code: 'too_big' }, { code: 'invalid_string' }]);
      });
    });
  });
});
