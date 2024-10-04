// src/stores/languageStore.spec.ts
import { useLanguageStore } from '@/stores/languageStore'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// Mock the api module
vi.mock('@/utils/api', () => ({
  default: {
    post: vi.fn()
  }
}))


describe('Language Store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()

    // Mock localStorage
    const localStorageMock = {
      getItem: vi.fn(),
      setItem: vi.fn(),
      clear: vi.fn()
    };
    Object.defineProperty(window, 'localStorage', { value: localStorageMock });

    // Mock window.supported_locales
    vi.stubGlobal('supported_locales', ['en', 'fr', 'es']);
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })



  it('initializes current locale correctly', () => {
    const store = useLanguageStore()

    // Test with stored locale
    vi.spyOn(localStorage, 'getItem').mockReturnValueOnce('fr')
    expect(store.initializeCurrentLocale('en-US')).toBe('en')

    // Test with device locale
    vi.spyOn(localStorage, 'getItem').mockReturnValueOnce(null)
    expect(store.initializeCurrentLocale('es-ES')).toBe('es')

    // Test with default locale
    vi.spyOn(localStorage, 'getItem').mockReturnValueOnce(null)
    expect(store.initializeCurrentLocale('de-DE')).toBe('de')
  })

})
