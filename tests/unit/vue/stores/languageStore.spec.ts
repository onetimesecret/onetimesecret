// src/stores/languageStore.spec.ts
import { useLanguageStore } from '@/stores/languageStore';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Mock the api module
vi.mock('@/utils/api', () => ({
  default: {
    post: vi.fn(),
  },
}));

describe('Language Store', () => {
  beforeEach(() => {
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

  it('initializes current locale correctly', () => {
    const store = useLanguageStore({
      deviceLocale: 'en',
      storageKey: 'custom_storage_key',
    });

    // Test with stored locale
    vi.spyOn(sessionStorage, 'getItem').mockReturnValueOnce('fr');
    expect(store.initializeLocale('en-US')).toBe('en');

    // Test with device locale
    vi.spyOn(sessionStorage, 'getItem').mockReturnValueOnce(null);
    expect(store.initializeLocale('es-ES')).toBe('es');

    // Test with default locale
    vi.spyOn(sessionStorage, 'getItem').mockReturnValueOnce(null);
    expect(store.initializeLocale('de-DE')).toBe('de');
  });
});
