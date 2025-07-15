// src/tests/setup/setupWindow.ts

import { vi } from 'vitest';
import { stateFixture } from '@/tests/fixtures/window.fixture';
import { type OnetimeWindow } from '@/types/declarations/window';

export const windowMock = {
  // Preserve any existing window properties you need
  location: window.location,
  document: window.document,
};

export function setupWindowState(newState: Partial<OnetimeWindow> = {}) {
  // Start with the full fixture, then merge existing global state (if any), then new state.
  // This ensures all keys are present.
  (window as any).onetime = {
    ...stateFixture, // Base with all required fields
    ...((window as any).onetime || {}), // Merge existing state if any
    ...newState, // Override with the new partial state
  } as OnetimeWindow;
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

  (window as any).onetime = minimalState as OnetimeWindow;
  // console.debug('setupEmptyWindowState', (window as any).onetime);
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
