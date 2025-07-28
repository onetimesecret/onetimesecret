// src/tests/setup-stores.ts

import { vi, beforeEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import axios, { AxiosInstance } from 'axios';
import { stateFixture } from './fixtures/window.fixture';
import type { OnetimeWindow } from '@/types/declarations/window';

// Create global test API instance that will be shared across tests
// This gets the mock adapter applied to it in individual test setups
let globalApi: AxiosInstance;

export function createSharedApiInstance(): AxiosInstance {
  if (!globalApi) {
    globalApi = axios.create({
      baseURL: 'http://localhost:3000',
      timeout: 5000,
    });
  }
  return globalApi;
}

// Mock Vue's inject function to return our test API
vi.mock('vue', async () => {
  const actual = await vi.importActual<typeof import('vue')>('vue');
  return {
    ...actual,
    inject: vi.fn((key: string) => {
      if (key === 'api') {
        return createSharedApiInstance();
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
