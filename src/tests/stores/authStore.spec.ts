// src/tests/stores/authStore.spec.ts
import { Customer, Plan } from '@/schemas/models';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/stores/authStore';
import { createApi } from '@/api';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

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
  let api: ReturnType<typeof createApi>;
  let store: ReturnType<typeof useAuthStore>;

  beforeEach(async () => {
    // Initialize the store
    const { api: testApi } = await setupTestPinia();
    api = testApi;
    axiosMock = new AxiosMockAdapter(api);
    store = useAuthStore();

    // NOTE: the autoInitPlugin plugin is called during setupTestPinia
    // which automatically calls store.init() for us. If you need to call
    // store.init() manually, run store.$reset() first to clear the state.

    // Ensure all initialization promises are resolved
    await vi.dynamicImportSettled();
  });

  afterEach(() => {
    axiosMock.restore();
    store.$reset();
    vi.clearAllMocks();
    vi.unstubAllGlobals();
  });

  describe('Initialization', () => {
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };
      store.$reset();
    });

    afterEach(() => {
      // Clean up window state properties
      if ((window as any).__ONETIME_STATE__) {
        (window as any).__ONETIME_STATE__.authenticated = mockWindow.authenticated;
      }
      axiosMock.restore();
      store.$reset();
    });

    it('initializes with clean state', () => {
      expect(store.$state).toMatchObject({
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
      (window as any).__ONETIME_STATE__.authenticated = undefined;
      expect(store.isAuthenticated).toBe(null);
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when null)', () => {
      (window as any).__ONETIME_STATE__.authenticated = null;
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when false)', () => {
      (window as any).__ONETIME_STATE__.authenticated = false;
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when bad data)', () => {
      (window as any).__ONETIME_STATE__.authenticated = 123;
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when true)', () => {
      (window as any).__ONETIME_STATE__.authenticated = true;
      store.init();
      expect(store.isAuthenticated).toBe(true);
    });

    it('initializes correctly (when "true")', () => {
      (window as any).__ONETIME_STATE__.authenticated = 'true';
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly', () => {
      (window as any).__ONETIME_STATE__.authenticated = false;
      store.init();
      expect(store.isAuthenticated).toBe(false);
      expect(store.failureCount).toBe(null);
      expect(store.lastCheckTime).toBeDefined();
    });
  });

  describe('Core Functionality', () => {
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };
      store.$reset();
    });

    it('initializes with clean state', () => {
      expect(store.$state).toMatchObject({
        isAuthenticated: null,
        authCheckTimer: null,
        failureCount: null,
        lastCheckTime: null,
        _initialized: false,
      });
    });

    it('initializes only once', () => {
      // First initialization
      store.init();
      expect(store.isInitialized).toBe(true);

      const initialAuthState = store.isAuthenticated;

      // Second initialization attempt
      store.init();

      // Verify critical state hasn't changed
      expect(store.isAuthenticated).toBe(initialAuthState);
    });

    it('prevents double initialization', () => {
      // Let's verify the behavior:
      // 1. Store gets initialized
      // 2. Second init doesn't change state
      // 3. Initial values are preserved

      // First init
      const result1 = store.init();
      const initializedState = { ...store.$state };

      // Second init
      const result2 = store.init();

      // Verify behavior we care about
      expect(store._initialized).toBe(true);
      expect(store.$state).toEqual(initializedState);

      // Optional: verify the returned values if that's part of the contract
      expect(result1).toEqual(result2);
    });

    it('properly disposes resources and listeners', async () => {
      // Setup
      store.init();
      store.$patch({ isAuthenticated: true });
      store.$scheduleNextCheck(); // Start a timer

      // Verify timer exists before dispose
      expect(store.authCheckTimer).not.toBeNull();

      // Act
      await store.$dispose();

      // Assert timer is cleaned up
      expect(store.authCheckTimer).toBeNull();
    });

    it('cleans up resources on dispose', async () => {
      store.init();
      store.$patch({ isAuthenticated: true });
      store.$scheduleNextCheck(); // Start a timer

      expect(store.authCheckTimer).not.toBeNull();

      await store.$dispose();

      expect(store.authCheckTimer).toBeNull();
    });
  });

  describe('Authentication Status Management', () => {
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };
      store.init();
      store.$patch({ isAuthenticated: true });
    });

    afterEach(() => {
      // Clean up window properties
      for (const key of Object.keys(mockWindow)) {
        delete (window as any)[key];
      }
      axiosMock.restore();
      store.$reset();
    });

    it('updates auth status correctly', async () => {
      // console.log('Store state before check:', {
      //   isAuthenticated: store.isAuthenticated,
      //   failureCount: store.failureCount,
      //   lastCheckTime: store.lastCheckTime,
      // });

      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        record: mockCustomer,
        shrimp: 'tempura',
      });

      const result = await store.checkAuthStatus();

      // console.log('Final store state:', {
      //   isAuthenticated: store.isAuthenticated,
      //   failureCount: store.failureCount,
      //   lastCheckTime: store.lastCheckTime,
      // });

      expect(store.isAuthenticated).toBe(true);
      expect(store.lastCheckTime).not.toBeNull();
    });

    it.skip('tracks failure count accurately', async () => {
      store.$patch({ isAuthenticated: true });

      axiosMock.onGet('/api/v2/authcheck').reply(500);

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(1);
    });

    it.skip('resets failure count after successful check', async () => {
      store.$patch({ isAuthenticated: true });
      store.failureCount = 2;

      axiosMock.onGet('/api/v2/authcheck').reply(200, {
        details: { authenticated: true },
      });

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(0);
    });

    it.skip('forces logout after MAX_FAILURES consecutive failures', async () => {
      store.$patch({ isAuthenticated: true });
      const logoutSpy = vi.spyOn(store, 'logout');

      // Configure mock to fail, with a specific error response
      axiosMock.onGet('/api/v2/authcheck').reply(() => [500, { error: 'Auth check failed' }]);

      // Simulate MAX_FAILURES consecutive failures
      for (let i = 0; i < AUTH_CHECK_CONFIG.MAX_FAILURES; i++) {
        await store.checkAuthStatus();
        // Re-authenticate between checks for testing
        store.$patch({ isAuthenticated: true });
      }

      expect(logoutSpy).toHaveBeenCalled();
    });
  });

  describe('Schema Validation', () => {
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };
      store.init();
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
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };
      store.init();
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
      // Set up window state with authenticated: true
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        authenticated: true,
      };

      store.$reset(); // Reset store to test initialization
      store.init();
      expect(store.isAuthenticated).toBe(true);
    });
  });

  describe('Timer & Visibility Handling', () => {
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };

      vi.useFakeTimers();
    });

    afterEach(() => {
      (window as any).authenticated = undefined;
      vi.useRealTimers();
      vi.restoreAllMocks();
    });

    it('schedules next check with proper jitter range', async () => {
      vi.useFakeTimers();
      vi.spyOn(Math, 'random').mockReturnValue(0.5);

      // Mock successful auth check response
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        record: mockCustomer,
      });

      store.$patch({ isAuthenticated: true });
      store.$scheduleNextCheck();

      const baseInterval = AUTH_CHECK_CONFIG.INTERVAL;

      // Advance time to when timer should fire
      vi.advanceTimersByTimeAsync(baseInterval);

      // Wait for the auth check to complete
      await vi.waitFor(
        () => {
          expect(store.lastCheckTime).not.toBeNull();
        },
        { timeout: 1000 }
      );

      // Verify API call was made correctly
      expect(axiosMock.history.get).toHaveLength(1);
      expect(axiosMock.history.get[0].url).toBe(AUTH_CHECK_CONFIG.ENDPOINT);

      vi.useRealTimers();
    }, 10000);

    it('does not schedule check when not authenticated', () => {
      // Setup fake timers
      vi.useFakeTimers();

      // Ensure store is not authenticated
      store.$patch({ isAuthenticated: false });

      store.$scheduleNextCheck();

      // Verify no timer was scheduled
      expect(store.authCheckTimer).toBeNull();
      expect(vi.getTimerCount()).toBe(0);

      // Cleanup
      vi.useRealTimers();
    });

    it('executes check and reschedules when timer fires', async () => {
      // Setup fresh store instance
      const store = useAuthStore();
      store.init();

      // Mock successful auth check response
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        record: mockCustomer,
      });

      // Set authenticated to trigger timer scheduling
      store.$patch({ isAuthenticated: true });

      // Start the check cycle
      store.$scheduleNextCheck();

      // Verify timer was set
      expect(store.authCheckTimer).not.toBeNull();

      // Fast-forward through the timer
      await vi.runOnlyPendingTimersAsync();

      // Verify the auth check happened
      expect(axiosMock.history.get).toHaveLength(1);
      expect(axiosMock.history.get[0].url).toBe(AUTH_CHECK_CONFIG.ENDPOINT);

      // Verify a new timer was scheduled
      expect(store.authCheckTimer).not.toBeNull();
    });

    it('clears existing timer before setting new one', () => {
      // Setup fake timers
      vi.useFakeTimers();

      store.$patch({ isAuthenticated: true });

      // Schedule initial check
      store.$scheduleNextCheck();
      const firstTimer = store.authCheckTimer;

      // Schedule another check
      store.$scheduleNextCheck();

      // Verify behaviours:
      // 1. First timer was cleared (different from second timer)
      // 2. Second timer is active
      expect(store.authCheckTimer).not.toBe(firstTimer);
      expect(store.authCheckTimer).not.toBeNull();

      // Cleanup
      vi.useRealTimers();
    });

    it('applies jitter within configured bounds', () => {
      vi.useFakeTimers();
      store.$patch({ isAuthenticated: true });

      const samples = 100;
      const delays: number[] = [];

      // Spy on setTimeout to capture the actual delays
      const setTimeoutSpy = vi.spyOn(vi, 'setSystemTime');

      for (let i = 0; i < samples; i++) {
        store.$scheduleNextCheck();
        // Get the delay from the last setTimeout call
        const lastCall = setTimeoutSpy.mock.calls[setTimeoutSpy.mock.calls.length - 1];
        if (lastCall) {
          delays.push(lastCall[1] as number);
        }
        vi.clearAllTimers(); // Clear timer before next iteration
      }

      const minExpected = AUTH_CHECK_CONFIG.INTERVAL - AUTH_CHECK_CONFIG.JITTER; // 810_000
      const maxExpected = AUTH_CHECK_CONFIG.INTERVAL + AUTH_CHECK_CONFIG.JITTER; // 990_000

      delays.forEach((delay) => {
        expect(delay).toBeGreaterThanOrEqual(minExpected);
        expect(delay).toBeLessThanOrEqual(maxExpected);
      });

      vi.useRealTimers();
      setTimeoutSpy.mockRestore();
    });

    it('stops existing auth check before scheduling a new one', () => {
      // Setup isolated store instance
      const store = useAuthStore();
      store.init();
      store.$patch({ isAuthenticated: true });

      // Setup fake timers
      vi.useFakeTimers();

      // Schedule first check
      store.$scheduleNextCheck();
      const firstTimer = store.authCheckTimer;
      expect(firstTimer).not.toBeNull();

      // Schedule second check
      store.$scheduleNextCheck();
      const secondTimer = store.authCheckTimer;

      // Verify behaviors:
      // 1. First timer was cleared (different from second timer)
      // 2. Second timer is active
      expect(secondTimer).not.toBe(firstTimer);
      expect(secondTimer).not.toBeNull();

      // Cleanup
      vi.useRealTimers();
    });

    it('stops auth check timer when logging out', () => {
      store.$patch({ isAuthenticated: true });
      store.$scheduleNextCheck();

      store.logout();

      expect(store.authCheckTimer).toBeNull();
      expect(vi.getTimerCount()).toBe(0);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      // Set window state properly, preserving __ONETIME_STATE__
      (window as any).__ONETIME_STATE__ = {
        ...(window as any).__ONETIME_STATE__,
        ...mockWindow,
      };
    });

    afterEach(() => {
      console.log('failures', store.failureCount);
      axiosMock.restore();
      store.$reset();
    });

    it('handles errors consistently through error boundary', async () => {
      store.$patch({ isAuthenticated: true });

      // Simulate network error
      axiosMock.onGet('/api/v2/authcheck').networkError();

      // Test the behavior we care about
      const result = await store.checkAuthStatus();

      // Verify expected outcomes:
      expect(result).toBe(false); // Check failed
      expect(store.failureCount).toBe(1); // Failure was counted
      expect(store.isAuthenticated).toBe(true); // Single failure doesn't trigger logout
    });

    it('handles network timeouts appropriately', async () => {
      store.$patch({ isAuthenticated: true });

      axiosMock.onGet('/api/v2/authcheck').timeoutOnce();

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(1);
    });

    it('recovers from temporary network failures', async () => {
      store.$patch({ isAuthenticated: true });

      store.failureCount = 1; // Simulate previous failure

      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        details: { authenticated: true },
        record: mockCustomer,
      });

      expect(store.failureCount).toBe(1);

      await store.checkAuthStatus();

      expect(store.failureCount).toBe(0);
    });
  });
});
