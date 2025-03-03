// tests/unit/vue/setupWindow.ts

import { vi } from 'vitest';
import { stateFixture } from './fixtures/window.fixture';

export const windowMock = {
  // Preserve any existing window properties you need
  location: window.location,
  document: window.document,
};

export function setupWindowState(state = stateFixture) {
  const windowMockWithState = {
    ...window,
    __ONETIME_STATE__: state,
  };

  return windowMockWithState;
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
