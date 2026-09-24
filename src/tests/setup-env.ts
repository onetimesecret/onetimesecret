// src/tests/setup-env.ts

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';

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

// `window.__BOOTSTRAP_ME__` is declared as `BootstrapPayload | undefined` in
// src/types/declarations/global.d.ts, so no cast is needed to reach the
// property itself. The value below only seeds the handful of fields tests
// actually rely on (locale/auth state), not a full BootstrapPayload, so it
// is asserted through `Pick<...>` first: that keeps every field name/type
// checked against the real contract, and only the final widening to the
// (necessarily fuller) BootstrapPayload type is an assertion.
type MinimalBootstrap = Pick<
  BootstrapPayload,
  'supported_locales' | 'fallback_locale' | 'default_locale' | 'locale' | 'authenticated'
>;

const bootstrapMock: MinimalBootstrap = {
  supported_locales: ['en', 'fr_CA', 'de_AT'],
  fallback_locale: 'en',
  default_locale: 'en',
  locale: 'en',
  authenticated: false,
};

window.__BOOTSTRAP_ME__ = bootstrapMock as BootstrapPayload;

// Mock __SENTRY_RELEASE__ global that Vite defines at build time
// This value is replaced by the actual git commit hash during production builds
// @see vite.config.ts getSentryRelease()
// @see src/types/declarations/vite-env.d.ts
(globalThis as Record<string, unknown>).__SENTRY_RELEASE__ = 'test-release';

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
