// src/tests/setup-env.ts

import type { OnetimeWindow } from '@/types/declarations/window';

// Handle known race condition in vue-i18n during test teardown.
// When jsdom tears down, async renders may still try to access window.
// This suppresses the benign "window is not defined" error from @intlify/core-base.
// See: https://github.com/intlify/vue-i18n/issues/1365
if (typeof process !== 'undefined') {
  process.on('unhandledRejection', (reason: unknown) => {
    const message = reason instanceof Error ? reason.message : String(reason);
    if (message.includes('window is not defined') && message.includes('intlify')) {
      // Suppress this specific i18n teardown race condition
      return;
    }
    // Re-throw other unhandled rejections
    throw reason;
  });
}

(window as OnetimeWindow).__BOOTSTRAP_STATE__ = {
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
