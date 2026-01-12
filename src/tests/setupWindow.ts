// src/tests/setupWindow.ts

import { type BootstrapPayload } from '@/types/declarations/bootstrap';
import { vi } from 'vitest';
import { stateFixture } from './fixtures/window.fixture';

export const windowMock = {
  // Preserve any existing window properties you need
  location: window.location,
  document: window.document,
};

export function setupWindowState(state = stateFixture) {
  // Keep any existing window state and override with new state
  window.__BOOTSTRAP_STATE__ = {
    ...(window.__BOOTSTRAP_STATE__ || {}),
    ...state,
  } as BootstrapPayload;
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

  window.__BOOTSTRAP_STATE__ = minimalState as BootstrapPayload;
  // console.debug('setupEmptyWindowState', window.__BOOTSTRAP_STATE__);
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
