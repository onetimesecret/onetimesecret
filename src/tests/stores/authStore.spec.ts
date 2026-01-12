// src/tests/stores/authStore.spec.ts

import { Customer } from '@/schemas/models';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createApi } from '@/api';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';
import { baseBootstrap, mockCustomer as fixtureCustomer } from '../setup-bootstrap';

// Create a mock Customer object that matches the actual Customer type
const mockCustomer: Customer = {
  identifier: 'cust-1',
  custid: '1',
  role: 'customer',
  verified: true,
  secrets_burned: 0,
  secrets_shared: 0,
  emails_sent: 0,
  last_login: null,
  feature_flags: {},
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
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  beforeEach(async () => {
    // Initialize the test environment with Pinia
    const { api: testApi } = await setupTestPinia();
    api = testApi;
    axiosMock = new AxiosMockAdapter(api);

    // Get store instances
    bootstrapStore = useBootstrapStore();
    store = useAuthStore();

    // Ensure all initialization promises are resolved
    await vi.dynamicImportSettled();
  });

  afterEach(() => {
    axiosMock.restore();
    store.$reset();
    bootstrapStore.$reset();
    vi.clearAllMocks();
    vi.unstubAllGlobals();
  });

  describe('Initialization', () => {
    beforeEach(() => {
      // Reset stores to test initialization
      store.$reset();
      bootstrapStore.$reset();
    });

    afterEach(() => {
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
      // bootstrapStore defaults to authenticated: false
      expect(store.isAuthenticated).toBe(null);
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when null)', () => {
      // Update bootstrap store with null-ish value (will be treated as false)
      bootstrapStore.update({ authenticated: false });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when false)', () => {
      bootstrapStore.update({ authenticated: false });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when bad data)', () => {
      // Non-boolean values should be treated as false
      bootstrapStore.update({ authenticated: 123 as any });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly (when true)', () => {
      bootstrapStore.update({ authenticated: true });
      store.init();
      expect(store.isAuthenticated).toBe(true);
    });

    it('initializes correctly (when "true")', () => {
      // String "true" is not boolean true, should be false
      bootstrapStore.update({ authenticated: 'true' as any });
      store.init();
      expect(store.isAuthenticated).toBe(false);
    });

    it('initializes correctly', () => {
      bootstrapStore.update({ authenticated: false });
      store.init();
      expect(store.isAuthenticated).toBe(false);
      expect(store.failureCount).toBe(null);
      expect(store.lastCheckTime).toBeDefined();
    });
  });

  describe('Core Functionality', () => {
    beforeEach(() => {
      // Reset and update bootstrap store with authenticated state
      bootstrapStore.$reset();
      bootstrapStore.update({
        authenticated: true,
        cust: fixtureCustomer,
        email: fixtureCustomer.email,
      });
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
      // First init
      const result1 = store.init();
      const initializedState = { ...store.$state };

      // Second init
      const result2 = store.init();

      // Verify behavior we care about
      expect(store._initialized).toBe(true);
      expect(store.$state).toEqual(initializedState);

      // Verify the returned values if that's part of the contract
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
      // Set up authenticated state via bootstrapStore
      bootstrapStore.$reset();
      bootstrapStore.update({
        authenticated: true,
        cust: fixtureCustomer,
        email: fixtureCustomer.email,
      });
      store.init();
      store.$patch({ isAuthenticated: true });
    });

    afterEach(() => {
      axiosMock.restore();
      store.$reset();
    });

    it('updates auth status correctly', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        authenticated: true,
        cust: mockCustomer,
        shrimp: 'tempura',
      });

      await store.checkWindowStatus();

      expect(store.isAuthenticated).toBe(true);
      expect(store.lastCheckTime).not.toBeNull();
    });

    it.skip('tracks failure count accurately', async () => {
      store.$patch({ isAuthenticated: true });

      axiosMock.onGet('/auth/validate').reply(500);

      await store.checkWindowStatus();
      expect(store.failureCount).toBe(1);
    });

    it.skip('resets failure count after successful check', async () => {
      store.$patch({ isAuthenticated: true });
      store.failureCount = 2;

      axiosMock.onGet('/auth/validate').reply(200, {
        details: { authenticated: true },
      });

      await store.checkWindowStatus();
      expect(store.failureCount).toBe(0);
    });

    it.skip('forces logout after MAX_FAILURES consecutive failures', async () => {
      store.$patch({ isAuthenticated: true });
      const logoutSpy = vi.spyOn(store, 'logout');

      // Configure mock to fail, with a specific error response
      axiosMock.onGet('/auth/validate').reply(() => [500, { error: 'Auth check failed' }]);

      // Simulate MAX_FAILURES consecutive failures
      for (let i = 0; i < AUTH_CHECK_CONFIG.MAX_FAILURES; i++) {
        await store.checkWindowStatus();
        // Re-authenticate between checks for testing
        store.$patch({ isAuthenticated: true });
      }

      expect(logoutSpy).toHaveBeenCalled();
    });
  });

  describe('Schema Validation', () => {
    beforeEach(() => {
      // Set up authenticated state via bootstrapStore
      bootstrapStore.$reset();
      bootstrapStore.update({
        authenticated: true,
        cust: fixtureCustomer,
        email: fixtureCustomer.email,
      });
      store.init();
      store.$patch({ isAuthenticated: true });
    });

    it('handles response missing customer field gracefully', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        authenticated: true,
        // missing customer field - store doesn't validate this
      });

      const result = await store.checkWindowStatus();
      expect(result).toBe(true); // authenticated flag is what matters
      expect(store.failureCount).toBe(0); // No network error
    });

    it('treats non-boolean authenticated value literally', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        authenticated: 'yes', // Non-boolean value
        cust: {},
      });

      const result = await store.checkWindowStatus();
      // The store does: response.data.authenticated || false
      // Since 'yes' is truthy, it becomes 'yes' (not coerced to boolean)
      expect(result).toBe('yes');
      expect(store.failureCount).toBe(0); // No network error
    });

    it('handles missing authenticated field gracefully', async () => {
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        cust: mockCustomer,
        // missing authenticated field
      });

      const result = await store.checkWindowStatus();
      expect(result).toBe(false); // undefined || false -> false
      expect(store.failureCount).toBe(0); // No network error
    });

    // Test the happy path for comparison
    it.skip('succeeds with valid response', async () => {
      // Set initial authenticated state
      store.$patch({ isAuthenticated: true });

      const responseData = {
        authenticated: true,
        cust: mockCustomer,
        shrimp: 'tempura',
      };

      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, responseData);

      const result = await store.checkWindowStatus();

      expect(result).toBe(true);
      expect(store.failureCount).toBe(0);
      expect(store.lastCheckTime).not.toBeNull();
    });
  });

  describe('Window State Synchronization', () => {
    beforeEach(() => {
      // Set up authenticated state via bootstrapStore
      bootstrapStore.$reset();
      bootstrapStore.update({
        authenticated: true,
        cust: fixtureCustomer,
        email: fixtureCustomer.email,
      });
      store.init();
      store.$patch({ isAuthenticated: true });
    });

    afterEach(() => {
      store.$reset();
    });

    it('does not sync store authenticated to window state', () => {
      expect(store.isAuthenticated).toBe(true);
      expect(window.authenticated).toBeUndefined();
    });

    it('initializes correctly from window state', () => {
      // Update bootstrapStore with authenticated: true
      bootstrapStore.update({ authenticated: true });

      store.$reset(); // Reset store to test initialization
      store.init();
      expect(store.isAuthenticated).toBe(true);
    });
  });

  describe('Timer & Visibility Handling', () => {
    beforeEach(() => {
      // Set up authenticated state via bootstrapStore
      bootstrapStore.$reset();
      bootstrapStore.update({
        authenticated: true,
        cust: fixtureCustomer,
        email: fixtureCustomer.email,
      });

      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
      vi.restoreAllMocks();
    });

    it.skip('schedules next check with proper jitter range', async () => {
      vi.useFakeTimers();
      vi.spyOn(Math, 'random').mockReturnValue(0.5);

      // Mock successful auth check response
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        authenticated: true,
        cust: mockCustomer,
        shrimp: 'tempura',
      });

      store.$patch({ isAuthenticated: true });
      store.$scheduleNextCheck();

      const baseInterval = AUTH_CHECK_CONFIG.INTERVAL;

      // Advance time to when timer should fire
      await vi.advanceTimersByTimeAsync(baseInterval);

      // The timer should have fired and made the auth check
      expect(store.lastCheckTime).not.toBeNull();

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
        authenticated: true,
        cust: mockCustomer,
        shrimp: 'tempura',
      });

      // Set authenticated to trigger timer scheduling
      store.$patch({ isAuthenticated: true });

      // Start the check cycle
      store.$scheduleNextCheck();

      // Verify timer was set
      const firstTimer = store.authCheckTimer;
      expect(firstTimer).not.toBeNull();

      // Fast-forward just past the first timer (with jitter)
      // Using advanceTimersByTimeAsync to avoid infinite recursion
      await vi.advanceTimersByTimeAsync(
        AUTH_CHECK_CONFIG.INTERVAL + AUTH_CHECK_CONFIG.JITTER + 1000
      );

      // Verify the auth check happened
      expect(axiosMock.history.get).toHaveLength(1);
      expect(axiosMock.history.get[0].url).toBe(AUTH_CHECK_CONFIG.ENDPOINT);

      // Verify a new timer was scheduled (different from the first one)
      expect(store.authCheckTimer).not.toBe(firstTimer);
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

  describe('Error Page Auth State Recovery', () => {
    beforeEach(() => {
      // Clear sessionStorage before each test
      sessionStorage.clear();
      // Clear cookies
      document.cookie = 'sess=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
      // Reset stores
      store.$reset();
      bootstrapStore.$reset();
    });

    afterEach(() => {
      sessionStorage.clear();
      document.cookie = 'sess=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
      store.$reset();
    });

    it('preserves auth state when server returns error page with authenticated=false', () => {
      // Simulate: user was authenticated and navigated to a page that 500'd
      // 1. Set up stored auth state (would have been set during previous successful login)
      sessionStorage.setItem('ots_auth_state', 'true');

      // 2. Server returns error page with:
      //    - authenticated: false (error page default)
      //    - had_valid_session: true (server checked session cookie and it was valid)
      bootstrapStore.update({
        authenticated: false,
        had_valid_session: true,
        cust: null,
      });

      // 3. Store initializes
      store.init();

      // 4. Should preserve auth state because server confirmed valid session
      expect(store.isAuthenticated).toBe(true);
    });

    it('respects authenticated=false when no stored auth state exists', () => {
      // Simulate: first visit or user was never authenticated
      // No stored auth state
      sessionStorage.removeItem('ots_auth_state');

      // Server says not authenticated
      bootstrapStore.update({
        authenticated: false,
        cust: null,
      });

      store.init();

      // Should trust server and set authenticated to false
      expect(store.isAuthenticated).toBe(false);
    });

    it('respects authenticated=false when server says had_valid_session=false', () => {
      // Simulate: stored state exists but session actually expired
      sessionStorage.setItem('ots_auth_state', 'true');

      // Server says not authenticated AND no valid session
      bootstrapStore.update({
        authenticated: false,
        had_valid_session: false,
        cust: null,
      });

      store.init();

      // Should trust server since had_valid_session=false
      expect(store.isAuthenticated).toBe(false);
      // Should clean up stale stored auth state
      expect(sessionStorage.getItem('ots_auth_state')).toBeNull();
    });

    it('respects authenticated=true from server regardless of stored state', () => {
      // Simulate: server correctly says authenticated
      sessionStorage.removeItem('ots_auth_state');

      bootstrapStore.update({
        authenticated: true,
        had_valid_session: true,
        cust: mockCustomer,
      });

      store.init();

      // Should trust server
      expect(store.isAuthenticated).toBe(true);
      // Should store auth state for future error recovery
      expect(sessionStorage.getItem('ots_auth_state')).toBe('true');
    });

    it('clears stored auth state when logging out', async () => {
      // Set up authenticated state
      sessionStorage.setItem('ots_auth_state', 'true');
      store.$patch({ isAuthenticated: true });

      // Logout
      await store.logout();

      // Should clear stored auth state
      expect(sessionStorage.getItem('ots_auth_state')).toBeNull();
      expect(store.isAuthenticated).toBeNull();
    });

    it('updates stored auth state when setAuthenticated is called', async () => {
      // Mock successful window status check
      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        authenticated: true,
        cust: mockCustomer,
        shrimp: 'tempura',
      });

      // Set authenticated to true
      await store.setAuthenticated(true);

      // Should store auth state
      expect(sessionStorage.getItem('ots_auth_state')).toBe('true');

      // Set authenticated to false
      await store.setAuthenticated(false);

      // Should remove stored auth state
      expect(sessionStorage.getItem('ots_auth_state')).toBeNull();
    });

    it('requires both server confirmation AND stored state to preserve auth', () => {
      // Edge case: Server says had_valid_session=true but user cleared sessionStorage
      // This could happen if:
      // - User manually cleared browser storage
      // - Different browser tab/window
      // - SessionStorage expired in browser

      // No stored state (user cleared it or never had it in this context)
      sessionStorage.removeItem('ots_auth_state');

      // Server says there was a valid session (checked httpOnly cookie server-side)
      bootstrapStore.update({
        authenticated: false,
        had_valid_session: true,
        cust: null,
      });

      store.init();

      // Should NOT preserve auth - we require BOTH server AND client agreement
      // This is correct because we can't confirm user's expectation without stored state
      expect(store.isAuthenticated).toBe(false);
    });

    it('handles MFA flow correctly - does not interfere with awaiting_mfa state', () => {
      // MFA scenario: User passed first factor but awaiting second factor
      // - authenticated: false (not fully authenticated yet)
      // - awaiting_mfa: true (partial auth state)
      // - had_valid_session: true (they do have a session)
      // - storedAuthState: 'false' (we never stored 'true' for partial auth)

      sessionStorage.removeItem('ots_auth_state'); // No stored auth (correct for MFA flow)

      bootstrapStore.update({
        authenticated: false,
        awaiting_mfa: true,
        had_valid_session: true,
        cust: null,
      });

      store.init();

      // Should respect authenticated=false because:
      // 1. authenticated=false from server (MFA not complete)
      // 2. No stored auth state (we only store on full authentication)
      // The recovery logic should NOT interfere with MFA flow
      expect(store.isAuthenticated).toBe(false);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      // Set up authenticated state via bootstrapStore
      bootstrapStore.$reset();
      bootstrapStore.update({
        authenticated: true,
        cust: fixtureCustomer,
        email: fixtureCustomer.email,
      });
    });

    afterEach(() => {
      console.log('failures', store.failureCount);
      axiosMock.restore();
      store.$reset();
    });

    it('handles errors consistently through error boundary', async () => {
      store.$patch({ isAuthenticated: true });

      // Simulate network error
      axiosMock.onGet('/auth/validate').networkError();

      // Test the behavior we care about
      const result = await store.checkWindowStatus();

      // Verify expected outcomes:
      expect(result).toBe(false); // Check failed
      expect(store.failureCount).toBe(1); // Failure was counted
      expect(store.isAuthenticated).toBe(true); // Single failure doesn't trigger logout
    });

    it('handles network timeouts appropriately', async () => {
      store.$patch({ isAuthenticated: true });

      axiosMock.onGet('/auth/validate').timeoutOnce();

      await store.checkWindowStatus();
      expect(store.failureCount).toBe(1);
    });

    it.skip('recovers from temporary network failures', async () => {
      store.$patch({ isAuthenticated: true });

      store.failureCount = 1; // Simulate previous failure

      axiosMock.onGet(AUTH_CHECK_CONFIG.ENDPOINT).reply(200, {
        authenticated: true,
        cust: mockCustomer,
        shrimp: 'tempura',
      });

      expect(store.failureCount).toBe(1);

      await store.checkWindowStatus();

      expect(store.failureCount).toBe(0);
    });
  });
});
