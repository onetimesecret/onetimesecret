// tests/unit/vue/setupWindow.ts

import { vi } from 'vitest';
import { stateFixture } from './fixtures/window.fixture';

export const windowMock = {
  // Preserve any existing window properties you need
  location: window.location,
  document: window.document,
};

export function setupWindowState(state = stateFixture) {
  // Keep any existing window state and override with new state
  window.__ONETIME_STATE__ = {
    ...(window.__ONETIME_STATE__ || {}),
    ...state,
  };
  return window;
}

export function setupEmptyWindowState() {
  // Don't use empty object - provide required i18n fields
  const minimalState = {
    supported_locales: ['en', 'fr', 'es'],
    fallback_locale: 'en',
    default_locale: 'en',
    locale: 'en',
  };

  window.__ONETIME_STATE__ = minimalState;
  console.debug('setupEmptyWindowState', window.__ONETIME_STATE__);
  return window;
}

export function setupWindowMedia(query = '(prefers-color-scheme: dark)') {
  window.matchMedia = vi.fn().mockImplementation((query) => ({
    matches: query === '(prefers-color-scheme: dark)', // we start dark
    media: query,
    onchange: null,
    addListener: vi.fn(), // deprecated
    removeListener: vi.fn(), // deprecated
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }));
}
