// tests/unit/vue/stores/windowStore.spec.ts

import { OnetimeWindow } from '@/types/declarations/window';
import { createTestingPinia } from '@pinia/testing';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from 'vue';

import { windowFixture } from '../fixtures/window.fixture';

const useWindowStore = () => {} // a stub

const mockWindow = {
  authenticated: true,
  cust: {
    id: 'cust_123',
    email: 'test@example.com',
    name: 'Test User',
  },
  email: 'test@example.com',
  baseuri: 'https://example.com',
  is_paid: true,
  domains_enabled: true,
  plans_enabled: true,
};

describe.skip('windowStore', () => {
  describe('Window Sanity Checks', () => {
    it('accesses window properties', () => {
      expect(window).toBeDefined();
      expect(window.global).toBeDefined();
      expect(window.fetch).toBeDefined();
      expect(window.performance).toBeDefined();
      expect(document).toBeDefined();
      expect(document.getRootNode()).toBeDefined();
    });

    it('manipulates DOM', () => {
      const div = document.createElement('div');
      div.innerHTML = 'Test';
      document.body.appendChild(div);

      expect(document.body.innerHTML).toContain('Test');
    });

    it('JSDOM provide support for events', () => {
      expect(window.addEventListener).toBeTypeOf('function');
    });

    it('localStorage is available', () => {
      expect(window.localStorage).toBeDefined();
    });

    it('location is available', () => {
      expect(window.location).toBeDefined();
    });

    it('mocks read-only properties', () => {
      const originalInnerWidth = window.innerWidth;

      Object.defineProperty(window, 'innerWidth', {
        configurable: true,
        value: 1024,
      });

      expect(window.innerWidth).toBe(1024);

      // Cleanup
      Object.defineProperty(window, 'innerWidth', {
        configurable: true,
        value: originalInnerWidth,
      });
    });
  });

  describe('Window Edge Cases', () => {
    it('mocks read-only properties', () => {
      const originalInnerWidth = window.innerWidth;

      Object.defineProperty(window, 'innerWidth', {
        configurable: true,
        value: 1024,
      });

      expect(window.innerWidth).toBe(1024);

      // Cleanup
      Object.defineProperty(window, 'innerWidth', {
        configurable: true,
        value: originalInnerWidth,
      });
    });

    it('handles undefined APIs', () => {
      // Some APIs might not be available in test environment
      if ('someAPI' in window) {
        // Test with API
      } else {
        // Skip or mock as needed
      }
    });
  });

  describe('Mock data', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useWindowStore>;

    beforeEach(() => {
      const app = createApp({});
      // `createTestingPinia()` creates a testing version of Pinia that mocks all
      // actions by default. Use `createTestingPinia({ stubActions: false })` if
      // you want to test actions. Otherwise they don't actually get called.
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);

      vi.stubGlobal('window', mockWindow);

      store = useWindowStore();
      // store.init();

      axiosMock = new AxiosMockAdapter(axios);
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
      axiosMock.restore();
    });

    it('initializes store with window values', () => {
      store.init();

      console.log('Store state after init:', store.isAuthenticated);
      expect(store.$state).toMatchObject({
        isLoading: false,
        authenticated: mockWindow.authenticated,
        cust: mockWindow.cust,
        email: mockWindow.email,
        baseuri: mockWindow.baseuri,
        is_paid: mockWindow.is_paid,
        domains_enabled: mockWindow.domains_enabled,
        plans_enabled: mockWindow.plans_enabled,
      });
    });

    it('initializes only once', () => {
      store.init();

      const initialState = { ...store.$state };

      // Try to init again with different window values
      Object.assign(window, { email: 'mysecret@example.com' });
      store.init();

      expect(store.$state).toEqual(initialState);
    });
  });

  describe('Full fixture', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useWindowStore>;

    beforeEach(() => {
      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);

      store = useWindowStore();
      axiosMock = new AxiosMockAdapter(axios);
    });

    afterEach(() => {
      axiosMock.restore();
      store.$reset();
    });

    it('initializes with the whole hog', () => {
      store = useWindowStore();

      // This approach is more reliable because:
      // 1. It avoids global mutation which can be problematic in tests
      // 2. Makes the dependency injection explicit
      // 3. Makes the tests more isolated and predictable
      store.init(windowFixture);

      const expectedState = {
        _initialized: true,
        isLoading: false,
        authenticated: windowFixture.authenticated,
        email: windowFixture.email,
        baseuri: windowFixture.baseuri,
        cust: windowFixture.cust,
        is_paid: windowFixture.is_paid,
        domains_enabled: windowFixture.domains_enabled,
        plans_enabled: windowFixture.plans_enabled,
      };

      expect(store.$state).toEqual(expectedState);
    });

    it('initializes with a partial hog', () => {
      const partialWindow = {
        authenticated: windowFixture.authenticated,
        email: windowFixture.email,
        baseuri: windowFixture.baseuri,
      };

      // store = useWindowStore();
      store.init(partialWindow as Partial<OnetimeWindow>);

      const expectedState = {
        isLoading: false,
        authenticated: windowFixture.authenticated,
        email: windowFixture.email,
        baseuri: windowFixture.baseuri,
      };

      expect(store.$state).toMatchObject(expectedState);
    });
  });

  describe.skip('fetch', () => {
    let store: ReturnType<typeof useWindowStore>;
    let axiosMock: AxiosMockAdapter;

    const updatedWindow = {
      ...mockWindow,
      authenticated: false,
      email: 'updated@example.com',
    };

    beforeEach(() => {
      store = useWindowStore();
      store.init();

      axiosMock = new AxiosMockAdapter(axios);
    });

    afterEach(() => {
      axiosMock.restore();
    });

    it('updates store with fetched data', async () => {
      axiosMock.onGet('/api/v2/window').reply(200, updatedWindow);

      await store.fetch();

      expect(store.authenticated).toBe(false);
      expect(store.email).toBe('updated@example.com');
    });

    it('handles network errors', async () => {
      axiosMock.onGet('/api/v2/window').networkError();
      const initialState = { ...store.$state };

      await store.fetch();

      expect(store.$state).toEqual(initialState);
    });

    it('sets loading state during fetch', async () => {
      axiosMock.onGet('/api/v2/window').reply(200, updatedWindow);

      expect(store.isLoading).toBe(false);
      const promise = store.fetch();
      expect(store.isLoading).toBe(true);
      await promise;
      expect(store.isLoading).toBe(false);
    });
  });
});
