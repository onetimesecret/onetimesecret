// tests/unit/vue/setup-stores.ts

import { vi, beforeEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { AxiosInstance } from 'axios';
import { stateFixture } from './fixtures/window.fixture';
import type { OnetimeWindow } from '@/types/declarations/window';

// Mock createApi function
const createApi = (): AxiosInstance => {
  return {
    defaults: {},
    getUri: () => '',
    request: () => Promise.resolve({ data: {} }),
    get: () => Promise.resolve({ data: {} }),
    delete: () => Promise.resolve({ data: {} }),
    head: () => Promise.resolve({ data: {} }),
    post: () => Promise.resolve({ data: {} }),
    put: () => Promise.resolve({ data: {} }),
    patch: () => Promise.resolve({ data: {} }),
    options: () => Promise.resolve({ data: {} }),
    interceptors: {
      request: { use: () => 0, eject: () => {} },
      response: { use: () => 0, eject: () => {} },
    },
  } as unknown as AxiosInstance;
};

// Create global test API instance
const globalApi = createApi();

// Mock Vue's inject function to return our test API
vi.mock('vue', async () => {
  const actual = await vi.importActual<typeof import('vue')>('vue');
  return {
    ...actual,
    inject: vi.fn((key: string) => {
      if (key === 'api') {
        return globalApi;
      }
      // For other injection keys, return undefined or call original
      return undefined;
    }),
  };
});

// Setup global Pinia instance and window state
beforeEach(() => {
  // Set up window state before creating stores
  (window as any).__ONETIME_STATE__ = {
    ...stateFixture,
  } as OnetimeWindow;

  const pinia = createTestingPinia({
    stubActions: false,
    createSpy: vi.fn,
  });
  setActivePinia(pinia);
});
