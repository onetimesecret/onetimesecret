// src/tests/setup-stores.ts

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { createTestingPinia } from '@pinia/testing';
import axios, { AxiosInstance } from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { setActivePinia } from 'pinia';
import { beforeEach, vi } from 'vitest';
import { baseBootstrap } from './fixtures/bootstrap.fixture';

// One axios instance per spec file (vitest isolates the module registry per
// file), shared by everything that asks for the API client:
//   - `setupTestPinia()` provides it to its app (`app.provide('api', ...)`),
//   - the `inject` fallback below hands it to stores and components created
//     with no provider at all.
// Exactly ONE mock adapter is wired to it at any time, and
// `getGlobalAxiosMock()` always returns that adapter. `setupTestPinia()` swaps
// in a fresh adapter through `installSharedAxiosMock()` and returns the same
// object as `axiosMock`, so a handler registered on either is the handler the
// store under test really hits.
let globalApi: AxiosInstance;
let globalMock: AxiosMockAdapter | null = null;

type SharedMockOptions = ConstructorParameters<typeof AxiosMockAdapter>[1];

// Fail loudly on any unmocked request - prevents jsdom XHR noise
// and ensures tests explicitly mock all API calls they depend on
const FAIL_LOUD: SharedMockOptions = { onNoMatch: 'throwException' };

export function createSharedApiInstance(): AxiosInstance {
  if (!globalApi) {
    globalApi = axios.create({
      baseURL: 'http://localhost:3000',
      timeout: 5000,
    });
    globalMock = new AxiosMockAdapter(globalApi, FAIL_LOUD);
  }
  return globalApi;
}

/**
 * Replace the shared instance's mock adapter with a fresh one and make it the
 * adapter `getGlobalAxiosMock()` returns.
 *
 * The previous adapter is restored first, so adapters never stack: a stacked
 * adapter keeps the one beneath it as its "original", and a later `restore()`
 * would silently re-arm handlers from an earlier test.
 */
export function installSharedAxiosMock(options?: SharedMockOptions): AxiosMockAdapter {
  const api = createSharedApiInstance();
  globalMock?.restore();
  globalMock = new AxiosMockAdapter(api, options);
  return globalMock;
}

/**
 * Get the axios mock adapter currently wired to the shared API instance.
 * After `setupTestPinia()` this is the same object as its `axiosMock`.
 *
 * @example
 * ```ts
 * const mock = getGlobalAxiosMock();
 * mock.onGet('/api/account').reply(200, { custid: 'test' });
 * ```
 */
export function getGlobalAxiosMock(): AxiosMockAdapter {
  createSharedApiInstance(); // Initialize if not already done
  return globalMock ?? installSharedAxiosMock(FAIL_LOUD);
}

// Vue's `inject`, with one fallback. The real lookup runs first, so whatever a
// test (or `setupTestPinia()`) provides is what stores and components receive,
// and provide/inject between components works as it does in the app. Only when
// nothing provides 'api' — a store created on the bare testing pinia below, a
// component mounted without `provide: { api }` — does the shared instance
// stand in, so `useApi()` does not throw in specs that never touch the network.
vi.mock('vue', async () => {
  const actual = await vi.importActual<typeof import('vue')>('vue');
  const MISSING = Symbol('inject-missing');
  const injectWithFallback = (key: unknown, ...rest: unknown[]) => {
    if (actual.hasInjectionContext()) {
      const found = actual.inject(key as string, MISSING as unknown);
      if (found !== MISSING) return found;
    }
    if (key === 'api') return createSharedApiInstance();
    if (rest.length === 0) return undefined;
    const [defaultValue, treatDefaultAsFactory] = rest;
    return treatDefaultAsFactory && typeof defaultValue === 'function'
      ? (defaultValue as () => unknown)()
      : defaultValue;
  };
  return {
    ...actual,
    inject: vi.fn(injectWithFallback),
  };
});

// Setup global Pinia instance and window state
beforeEach(() => {
  // Set up window state before creating stores using modern bootstrap fixture
  (window as any).__BOOTSTRAP_ME__ = {
    ...baseBootstrap,
  } as BootstrapPayload;

  const pinia = createTestingPinia({
    stubActions: false,
    createSpy: vi.fn,
  });
  setActivePinia(pinia);
});
