// src/tests/setup-stores.ts

import type { BootstrapPayload } from '@/types/declarations/bootstrap';
import { createTestingPinia } from '@pinia/testing';
import axios, { AxiosInstance } from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { setActivePinia } from 'pinia';
import { beforeEach, vi } from 'vitest';
import { stateFixture } from './fixtures/window.fixture';

// Create global test API instance that will be shared across tests
// This gets the mock adapter applied to it in individual test setups
let globalApi: AxiosInstance;
let globalMock: AxiosMockAdapter;

export function createSharedApiInstance(): AxiosInstance {
  if (!globalApi) {
    globalApi = axios.create({
      baseURL: 'http://localhost:3000',
      timeout: 5000,
    });
    // Fail loudly on any unmocked request - prevents jsdom XHR noise
    // and ensures tests explicitly mock all API calls they depend on
    globalMock = new AxiosMockAdapter(globalApi, {
      onNoMatch: 'throwException',
    });
  }
  return globalApi;
}

/**
 * Get the global axios mock adapter for configuring responses in tests.
 * Use this to set up specific mock responses before test actions.
 *
 * @example
 * ```ts
 * const mock = getGlobalAxiosMock();
 * mock.onGet('/api/account/account').reply(200, { custid: 'test' });
 * ```
 */
export function getGlobalAxiosMock(): AxiosMockAdapter {
  if (!globalMock) {
    createSharedApiInstance(); // Initialize if not already done
  }
  return globalMock;
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
  (window as any).__BOOTSTRAP_STATE__ = {
    ...stateFixture,
  } as BootstrapPayload;

  const pinia = createTestingPinia({
    stubActions: false,
    createSpy: vi.fn,
  });
  setActivePinia(pinia);
});
