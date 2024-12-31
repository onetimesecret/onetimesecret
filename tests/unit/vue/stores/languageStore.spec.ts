// src/stores/languageStore.spec.ts
import { SESSION_STORAGE_KEY, useLanguageStore } from '@/stores/languageStore';
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
      const setupErrorHandlerSpy = vi
        .spyOn(sessionStorage, 'getItem')
        .mockReturnValueOnce(null);
      expect(store.currentLocale).toBe('es');
      expect(setupErrorHandlerSpy).toBeCalledTimes(0);
    });

    it('initializes with deviceLocale (de)', () => {
      const store = useLanguageStore();
      store.init(undefined, {
        deviceLocale: 'de',
      });
      expect(store.currentLocale).toBe('de');
    });

    it('initializes with stored locale', () => {
      const store = useLanguageStore();
      store.init();
      const setupErrorHandlerSpy = vi
        .spyOn(sessionStorage, 'getItem')
        .mockReturnValueOnce('fr');
      expect(store.currentLocale).toBe('fr');
      expect(setupErrorHandlerSpy).toBeCalled();
    });
  });

  describe('Language Updates', () => {
    it('should set current locale correctly', () => {
      const store = useLanguageStore();
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
      const store = useLanguageStore();
      store.supportedLocales = ['en', 'fr'];

      expect(store.determineLocale('fr-FR')).toBe('fr');
      expect(store.determineLocale('invalid')).toBe('en'); // Default
      expect(store.determineLocale('fr')).toBe('fr');
    });

    it('should handle updateLanguage correctly', async () => {
      const store = useLanguageStore();
      const api = { post: vi.fn().mockResolvedValue({}) };
      store.setupErrorHandler(api);

      await store.updateLanguage('fr');
      expect(api.post).toHaveBeenCalledWith('/api/v2/account/update-locale', {
        locale: 'fr',
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle errors in updateLanguage', async () => {
      const store = useLanguageStore();
      const api = { post: vi.fn().mockRejectedValue(new Error('Network error')) };
      store.setupErrorHandler(api);

      await expect(store.updateLanguage('invalid!')).rejects.toThrow();
    });
  });
});
