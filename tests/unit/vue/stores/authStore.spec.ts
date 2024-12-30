// tests/unit/vue/stores/windowStore.spec.ts
import { logoutPlugin } from '@/plugins/pinia/logoutPlugin';
import { Customer, Plan } from '@/schemas/models';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/stores/authStore';
import { createApi } from '@/utils';
import { createTestingPinia } from '@pinia/testing';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { setActivePinia } from 'pinia';
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
  let axiosMock: AxiosMockAdapter;
  let axiosInstance: ReturnType<typeof createApi>;

  beforeEach(() => {
    // Create a fresh axios instance for testing
    axiosInstance = createApi();
    // Create the mock adapter with this instance
    axiosMock = new AxiosMockAdapter(axiosInstance);

    const app = createApp({});
    // `createTestingPinia()` creates a testing version of Pinia that mocks all
    // actions by default. Use `createTestingPinia({ stubActions: false })` if
    // you want to test actions. Otherwise they don't actually get called.
    const pinia = createTestingPinia({ stubActions: false });
    app.use(pinia);
  });

  afterEach(() => {
    axiosMock.restore();
  });

  describe('Mock data', () => {
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
      store.init(axiosInstance);
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
      axiosMock.restore();
      store.reset();
      vi.unstubAllGlobals();
      vi.clearAllMocks();
    });

    it('initializes store with window values', () => {
      expect(store.$state).toMatchObject({
        isAuthenticated: true,
      });
    });
  });

  describe('Initialization', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      store = useAuthStore();

      axiosMock = new AxiosMockAdapter(axios);
    });

    afterEach(() => {
      // Clean up window properties
      (window as any).authenticated = undefined;
      axiosMock.restore();
      store.reset();
    });

    it('initializes with clean state', () => {
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
      store.init(axiosInstance);
      expect(store.isInitialized).toBe(true);
    });

    it('initializes correctly (when undefined)', () => {
      expect(store.isAuthenticated).toBe(null);
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when null)', () => {
      Object.assign(window, { authenticated: null });
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when false)', () => {
      Object.assign(window, { authenticated: false });
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when bad data)', () => {
      Object.assign(window, { authenticated: 123 });
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when true)', () => {
      Object.assign(window, { authenticated: true });
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(true);
    });

    it('initializes correctly (when "true")', () => {
      Object.assign(window, { authenticated: 'true' });
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly', () => {
      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(false);
      expect(store.failureCount).toBe(null);
      expect(store.lastCheckTime).toBeDefined();
    });
  });

  describe('Core Functionality', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      // Create fresh pinia instance with non-stubbed actions
      setActivePinia(createTestingPinia({ stubActions: false }));
      store = useAuthStore();
    });

    it('initializes with clean state', () => {
      expect(store.$state).toMatchObject({
        isLoading: false,
        isAuthenticated: null,
        authCheckTimer: null,
        failureCount: null,
        lastCheckTime: null,
        _initialized: false,
      });
    });

    it('prevents double initialization', () => {
      const setupErrorHandlerSpy = vi.spyOn(store, 'setupErrorHandler');

      store.init(axiosInstance);
      store.init(axiosInstance); // Second call should be ignored

      expect(setupErrorHandlerSpy).toHaveBeenCalledTimes(1);
      expect(store._initialized).toBe(true);
    });

    it('handles proper error handler setup', () => {
      store.setupErrorHandler();

      expect(store._errorHandler).not.toBeNull();
      expect(store._api).not.toBeNull();
      expect(typeof store._errorHandler?.withErrorHandling).toBe('function');
    });

    it('properly disposes resources and listeners', () => {
      const stopAuthCheckSpy = vi.spyOn(store, '$stopAuthCheck');

      store.init(axiosInstance);
      store.$dispose();

      expect(stopAuthCheckSpy).toHaveBeenCalled();
      expect(store.authCheckTimer).toBeNull();
    });
  });

  describe('Authentication Status Management', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      store = useAuthStore();
      store.init(axiosInstance);
      store.$patch({ isAuthenticated: true });
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
      axiosMock.restore();
      store.reset();
    });

    it('updates auth status correctly', async () => {
      console.log('Store state before check:', store.$state);
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        record: mockCustomer,
        shrimp: 'tempura',
      });

      const result = await store.checkAuthStatus();
      console.log('Check result:', result);
      console.log('Final store state:', store.$state);

      expect(store.isAuthenticated).toBe(true);
      expect(store.lastCheckTime).not.toBeNull();
    });

    it.skip('tracks failure count accurately', async () => {
      store.isAuthenticated = true;

      axiosMock.onGet('/api/v2/authcheck').reply(500);

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(1);
    });

    it.skip('resets failure count after successful check', async () => {
      store.isAuthenticated = true;
      store.failureCount = 2;

      axiosMock.onGet('/api/v2/authcheck').reply(200, {
        details: { authenticated: true },
      });

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(0);
    });

    it.skip('forces logout after MAX_FAILURES consecutive failures', async () => {
      store.isAuthenticated = true;
      const logoutSpy = vi.spyOn(store, 'logout');

      // Configure mock to fail, with a specific error response
      axiosMock.onGet('/api/v2/authcheck').reply(() => {
        return [500, { error: 'Auth check failed' }];
      });

      // Simulate MAX_FAILURES consecutive failures
      for (let i = 0; i < AUTH_CHECK_CONFIG.MAX_FAILURES; i++) {
        await store.checkAuthStatus();
        // Re-authenticate between checks for testing
        if (i < AUTH_CHECK_CONFIG.MAX_FAILURES - 1) store.isAuthenticated = true;
      }

      expect(logoutSpy).toHaveBeenCalled();
    });
  });

  describe('Schema Validation', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      store = useAuthStore();
      store.init(axiosInstance);
      store.$patch({ isAuthenticated: true });
    });

    it('fails when response is missing record field', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        // missing required record field
      });

      const result = await store.checkAuthStatus();
      expect(result).toBe(false);
      expect(store.failureCount).toBe(1);
    });

    it('fails when authenticated is wrong type', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: 'yes' }, // should be boolean
        record: {},
      });

      const result = await store.checkAuthStatus();
      expect(result).toBe(false);
      expect(store.failureCount).toBe(1);
    });

    it('fails when details is missing', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        record: mockCustomer,
        // missing required details field
      });

      const result = await store.checkAuthStatus();
      expect(result).toBe(false);
      expect(store.failureCount).toBe(1);
    });

    // Test the happy path for comparison
    it('succeeds with valid response', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        record: mockCustomer,
      });

      const result = await store.checkAuthStatus();
      expect(result).toBe(true);
      expect(store.failureCount).toBe(0);
      expect(store.lastCheckTime).not.toBeNull();
    });
  });

  describe('Window State Synchronization', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      store = useAuthStore();
      store.init(axiosInstance);
      store.$patch({ isAuthenticated: true });
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
    });

    it('does not sync store authenticated to window state', () => {
      expect(store.isAuthenticated).toBe(true);
      expect(window.authenticated).toBeUndefined();
    });

    it('initializes correctly from window state', () => {
      vi.stubGlobal('window', { authenticated: true });

      store.init(axiosInstance);
      expect(store.isAuthenticated).toBe(true);

      vi.unstubAllGlobals();
    });
  });

  describe('Timer & Visibility Handling', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      // We need attach pinia to an app instance to use plugins and the
      // order is important. Pinia docs mention it  on the plugins page.
      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      setActivePinia(pinia);
      pinia.use(logoutPlugin);

      store = useAuthStore();
      vi.useFakeTimers();
    });

    afterEach(() => {
      (window as any).authenticated = undefined;
      vi.useRealTimers();
      vi.restoreAllMocks();
    });

    it('schedules next check with proper jitter range', () => {
      store.isAuthenticated = true;
      vi.spyOn(window, 'setTimeout');
      vi.spyOn(Math, 'random').mockReturnValue(0.5);

      store.$scheduleNextCheck();

      const baseInterval = AUTH_CHECK_CONFIG.INTERVAL; // 900000
      const jitter = AUTH_CHECK_CONFIG.JITTER; // 90000

      expect(setTimeout).toHaveBeenCalledTimes(1);
      // expect(setTimeout).toHaveBeenCalledWith(() => {}, expect.closeTo(baseInterval, jitter));
    });

    it('does not schedule check when not authenticated', () => {
      vi.spyOn(window, 'setTimeout');

      store.$scheduleNextCheck();

      expect(setTimeout).not.toHaveBeenCalled();
      expect(store.authCheckTimer).toBeNull();
    });

    it('executes check and reschedules when timer fires', async () => {
      store.isAuthenticated = true;
      vi.spyOn(store, 'checkAuthStatus').mockResolvedValue(true);
      vi.spyOn(store, '$scheduleNextCheck');

      store.$scheduleNextCheck();

      // Fast-forward past the scheduled time
      vi.runOnlyPendingTimers();

      expect(store.checkAuthStatus).toHaveBeenCalled();
      expect(store.$scheduleNextCheck).toHaveBeenCalled();
    });

    it('clears existing timer before setting new one', () => {
      store.isAuthenticated = true;
      vi.spyOn(window, 'clearTimeout');

      // Schedule initial check
      store.$scheduleNextCheck();
      const firstTimer = store.authCheckTimer;

      // Schedule another check
      store.$scheduleNextCheck();

      expect(clearTimeout).toHaveBeenCalledWith(firstTimer);
      expect(store.authCheckTimer).not.toBe(firstTimer);
    });

    it('applies jitter within configured bounds', () => {
      store.isAuthenticated = true;
      const setTimeoutSpy = vi.spyOn(window, 'setTimeout');

      // Test multiple random values to verify bounds
      const samples = 100;
      const times: number[] = [];

      for (let i = 0; i < samples; i++) {
        store.$scheduleNextCheck();
        // Get the time argument passed to setTimeout using the spy
        const time = setTimeoutSpy.mock.calls[i][1] as number;
        times.push(time);
      }

      const minExpected = AUTH_CHECK_CONFIG.INTERVAL - AUTH_CHECK_CONFIG.JITTER;
      const maxExpected = AUTH_CHECK_CONFIG.INTERVAL + AUTH_CHECK_CONFIG.JITTER;

      times.forEach((time) => {
        expect(time).toBeGreaterThanOrEqual(minExpected);
        expect(time).toBeLessThanOrEqual(maxExpected);
      });
    });

    it('stops existing auth check before scheduling a new one', () => {
      store.isAuthenticated = true;

      // Mock Math.random to return 0.5 (no jitter)
      const mathRandomSpy = vi.spyOn(Math, 'random').mockReturnValue(0.5);

      // Spy on $stopAuthCheck
      const stopAuthCheckSpy = vi.spyOn(store, '$stopAuthCheck');

      // Call the method to schedule the next check
      store.$scheduleNextCheck();

      // Assert $stopAuthCheck was called
      expect(stopAuthCheckSpy).toHaveBeenCalled();

      // Restore Math.random
      mathRandomSpy.mockRestore();
    });

    it('stops auth check timer when logging out', () => {
      store.isAuthenticated = true;
      store.$scheduleNextCheck();

      store.logout();

      expect(store.authCheckTimer).toBeNull();
      expect(vi.getTimerCount()).toBe(0);
    });
  });

  describe.skip('Error Handling', () => {
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      // Create fresh pinia instance with non-stubbed actions
      setActivePinia(createTestingPinia({ stubActions: false }));
      store = useAuthStore();
      vi.useFakeTimers();
    });

    it('handles network timeouts appropriately', async () => {
      store.isAuthenticated = true;

      vi.mocked(axios.get).mockRejectedValueOnce(new Error('Network timeout'));

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(1);
    });

    it('recovers from temporary network failures', async () => {
      store.isAuthenticated = true;
      store.failureCount = 1; // Simulate previous failure

      vi.mocked(axios.get).mockResolvedValueOnce({
        data: {
          details: { authenticated: true },
        },
      });

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(0);
    });

    it('integrates with error handler for consistent error management', async () => {
      store.isAuthenticated = true;
      const errorHandlerSpy = vi.spyOn(store._errorHandler!, 'withErrorHandling');

      vi.mocked(axios.get).mockRejectedValueOnce(new Error('Test error'));

      await store.checkAuthStatus();

      expect(errorHandlerSpy).toHaveBeenCalled();
    });
  });
});
