import type { OnetimeWindow } from '@/types/declarations/window';

(window as OnetimeWindow).__ONETIME_STATE__ = {
  supported_locales: ['en', 'fr_CA', 'de_AT'],
  fallback_locale: 'en',
  default_locale: 'en',
  locale: 'en',
  authenticated: false,
};

// Mock localStorage for tests
const localStorageMock = {
  getItem: () => null,
  setItem: () => {},
  removeItem: () => {},
  clear: () => {},
  key: () => null,
  length: 0,
};

Object.defineProperty(window, 'localStorage', {
  value: localStorageMock,
  writable: true,
});

console.log('Window state initialized in setup-env.js');
