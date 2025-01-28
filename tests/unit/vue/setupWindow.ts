import { afterAll } from 'vitest';
import { stateFixture } from './fixtures/window.fixture';

// Initialize window state before any tests run
window.__ONETIME_STATE__ = stateFixture;

// Clean up after all tests
afterAll(() => {
  window.__ONETIME_STATE__ = undefined;
});
