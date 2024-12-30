// tests/unit/vue/stores/windowStore.spec.ts
import { Customer, Plan } from '@/schemas/models';
import { useAuthStore } from '@/stores/authStore';
import { createTestingPinia } from '@pinia/testing';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from 'vue';

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

const mockPlan: Plan = {
  identifier: 'basic-plan',
  planid: 'basic',
  price: 0,
  discount: 0,
  options: {
    ttl: 7 * 24 * 60 * 60, // 7 days in seconds
    size: 1024 * 1024, // 1MB in bytes
    api: false,
    name: 'Basic Plan',
  },
};

// Create a mock Customer object that matches the actual Customer type
const mockCustomer: Customer = {
  identifier: 'cust-1',
  custid: '1',
  role: 'customer', // Changed from 'user' to valid enum value
  planid: 'basic',
  plan: mockPlan,
  verified: true,
  secrets_burned: 0,
  secrets_shared: 0,
  emails_sent: 0,
  last_login: null,
  feature_flags: {},
  // Use proper Date objects
  updated: new Date(Math.floor(Date.now() / 1000) * 1000),
  created: new Date(Math.floor(Date.now() / 1000) * 1000),
  secrets_created: 0,
  active: true,
  locale: 'en-US',
  stripe_checkout_email: 'john@example.com',
  stripe_subscription_id: 'sub_123456',
  stripe_customer_id: 'cus_123456',
};

describe('authStore', () => {
  describe('Mock data', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      const app = createApp({});
      // `createTestingPinia()` creates a testing version of Pinia that mocks all
      // actions by default. Use `createTestingPinia({ stubActions: false })` if
      // you want to test actions. Otherwise they don't actually get called.
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);

      vi.stubGlobal('window', mockWindow);

      store = useAuthStore();

      axiosMock = new AxiosMockAdapter(axios);
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
      axiosMock.restore();
      store.reset();
      vi.unstubAllGlobals();
    });

    it('initializes store with window values', () => {
      store.init();
      expect(store.$state).toMatchObject({
        isAuthenticated: true,
      });
    });
  });

  describe('Initialization', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      const app = createApp({});
      // `createTestingPinia()` creates a testing version of Pinia that mocks all
      // actions by default. Use `createTestingPinia({ stubActions: false })` if
      // you want to test actions. Otherwise they don't actually get called.
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);

      store = useAuthStore();

      axiosMock = new AxiosMockAdapter(axios);
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
      axiosMock.restore();
      store.reset();
    });

    it('initializes with clean state', () => {
      console.log('Store state after init:', store.$state);
      expect(store.$state).toMatchObject({
        isLoading: false,
        isAuthenticated: null,
        authCheckTimer: null,
        failureCount: null,
        lastCheckTime: null,
        _initialized: false,
      });
    });

    it('initializes with flag', () => {
      expect(store.isInitialized).toBe(false);
      store.init();
      expect(store.isInitialized).toBe(true);
    });

    it('initializes correctly (when undefined)', () => {
      expect(store.isAuthenticated).toBe(null);
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when null)', () => {
      Object.assign(window, { authenticated: null });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when false)', () => {
      Object.assign(window, { authenticated: false });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when bad data)', () => {
      Object.assign(window, { authenticated: 123 });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when true)', () => {
      Object.assign(window, { authenticated: true });
      store.init();
      expect(store.isAuthenticated).toBe(true);
    });

    it('initializes correctly (when "true")', () => {
      Object.assign(window, { authenticated: 'true' });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });
  });
});
