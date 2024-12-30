import { logoutPlugin } from '@/plugins/pinia/logoutPlugin';
import { Customer, Plan } from '@/schemas/models';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/stores/authStore';
import { createApi } from '@/utils/api';
import axios, { AxiosError } from 'axios';
import { createPinia, Pinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, Mock, vi } from 'vitest';
import { Router } from 'vue-router';

vi.mock('axios');

// Mock the api module
vi.mock('@/utils/api', () => ({
  default: {
    post: vi.fn(),
  },
  createApi: () => ({
    get: vi.fn(),
    post: vi.fn(),
  }),
}));

const mockRouter = {
  push: vi.fn(),
  // Add other router methods you might use in your tests
};

vi.mock('vue-router', () => ({
  createRouter: vi.fn(() => mockRouter),
  createWebHistory: vi.fn(),
  useRouter: vi.fn(() => mockRouter),
}));

// Create a mock Plan object
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

// Define proper types for our mocks
interface MockWindow extends Partial<Window> {
  authenticated: boolean;
  cust: Customer | null;
  setTimeout: Mock;
  clearTimeout: Mock;
}

interface MockDocument extends Partial<Document> {
  visibilityState: DocumentVisibilityState;
  addEventListener: Mock;
  removeEventListener: Mock;
  dispatchEvent: Mock;
}

export const createAuthenticatedStore = () => {
  const store = useAuthStore();
  store.isAuthenticated = true;
  store.customer = mockCustomer;
  return store;
};

export const simulateVisibilityChange = (visibilityState: DocumentVisibilityState) => {
  Object.defineProperty(document, 'visibilityState', {
    value: visibilityState,
    configurable: true,
  });
  document.dispatchEvent(new Event('visibilitychange'));
};

describe('Auth Store', () => {
  let router: Router;
  let pinia: Pinia;
  let store: ReturnType<typeof useAuthStore>;
  let mockWindow: MockWindow;
  let mockDocument: MockDocument;
  const originalWindow = { ...window };
  const originalDocument = { ...document };

  beforeEach(() => {
    // Create fresh pinia instance
    pinia = createPinia();
    pinia.use(logoutPlugin);

    // Ensure clean setup
    setActivePinia(pinia);
    store = useAuthStore();

    // Create fresh mock objects each time
    mockWindow = {
      authenticated: false,
      cust: null,
      setTimeout: vi.fn(),
      clearTimeout: vi.fn(),
    };

    mockDocument = {
      visibilityState: 'visible',
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    };

    // Use Object.defineProperties for more reliable stubbing
    Object.defineProperties(window, {
      authenticated: {
        get: () => mockWindow.authenticated,
        set: (val) => {
          mockWindow.authenticated = val;
        },
        configurable: true,
      },
      cust: {
        get: () => mockWindow.cust,
        set: (val) => {
          mockWindow.cust = val;
        },
        configurable: true,
      },
    });

    // Apply stubs with type assertions
    vi.stubGlobal('window', mockWindow as unknown as Window);
    vi.stubGlobal('document', mockDocument as unknown as Document);
  });

  afterEach(() => {
    store.$dispose();
    pinia = null as unknown as Pinia;
    vi.clearAllMocks();
    vi.clearAllTimers();

    // Reset window state explicitly
    mockWindow = {
      authenticated: false,
      cust: null,
      setTimeout: vi.fn(),
      clearTimeout: vi.fn(),
    };
    vi.stubGlobal('window', mockWindow);

    // Restore original objects
    Object.defineProperties(window, Object.getOwnPropertyDescriptors(originalWindow));
    vi.stubGlobal('document', originalDocument);
  });

  describe('Initialization', () => {
    it('initializes with clean state', () => {
      const store = useAuthStore();
      expect(store.initialized).toBe(false);
      store.initialize();
      expect(store.initialized).toBe(true);
    });

    it('initializes correctly', () => {
      // const store = useAuthStore();
      const setupErrorHandlerSpy = vi.spyOn(store, 'setupErrorHandler');

      vi.stubGlobal('authenticated', true);
      vi.stubGlobal('cust', mockCustomer);

      store.initialize();

      expect(store.isAuthenticated).toBe(true);
      expect(store.customer).toEqual(mockCustomer);
      expect(setupErrorHandlerSpy).toHaveBeenCalled();

      vi.unstubAllGlobals();
    });

    it('prevents double initialization', () => {
      const store = useAuthStore();
      const initSpy = vi.spyOn(store, 'setupErrorHandler');

      store.initialize();
      store.initialize(); // Second call

      expect(initSpy).toHaveBeenCalledTimes(1);
    });

    it('should properly initialize with window state', () => {
      // Setup window state before initialization
      (window as any).authenticated = true;
      (window as any).cust = mockCustomer;

      store.initialize();

      expect(store.isAuthenticated).toBe(true);
      expect(store.customer).toEqual(mockCustomer);
    });

    it('verify window state', async () => {
      const mockWindow = {
        authenticated: false,
        cust: null as Customer | null, // Explicit typing
        setTimeout: vi.fn(),
        clearTimeout: vi.fn(),
      };

      vi.stubGlobal('window', mockWindow);

      mockWindow.authenticated = true;
      mockWindow.cust = mockCustomer; // Now TypeScript knows this is valid

      expect(window.authenticated).toBe(true);
      expect(window.cust).toEqual(mockCustomer);
    });

    it('initializes with proper window state synchronization', async () => {
      // Setup mock window before store initialization
      const mockWindow = {
        authenticated: true,
        cust: mockCustomer,
        setTimeout: vi.fn(),
        clearTimeout: vi.fn(),
      };

      vi.stubGlobal('window', mockWindow);

      const store = useAuthStore();

      // Spy on initialize without mocking implementation
      const initializeSpy = vi.spyOn(store, 'initialize');

      store.initialize();

      expect(initializeSpy).toHaveBeenCalled();
      expect(store.isAuthenticated).toBe(true);
      expect(store.customer).toEqual(mockCustomer);

      // Verify window sync
      expect(window.authenticated).toBe(true);
      expect(window.cust).toEqual(mockCustomer);
    });

    // Add test for visibility change handling
    it.skip('performs auth check when tab becomes visible after inactivity', async () => {
      // Setup
      vi.useFakeTimers();
      const store = useAuthStore();

      // Set window state first since initialize() reads from it
      vi.stubGlobal('authenticated', true);
      vi.stubGlobal('cust', mockCustomer);

      store.initialize();

      // Mock API response
      vi.mocked(axios.get).mockResolvedValueOnce({
        data: {
          record: mockCustomer,
          details: { authenticated: true },
        },
      });

      console.log('Initial state:', {
        isAuthenticated: store.isAuthenticated,
        windowAuth: window.authenticated,
        lastCheckTime: store.lastCheckTime,
        needsCheck: store.needsCheck,
        initialized: store.initialized,
        visibilityState: document.visibilityState,
      });

      // First make tab hidden
      Object.defineProperty(document, 'visibilityState', {
        configurable: true,
        value: 'hidden',
      });
      document.dispatchEvent(new Event('visibilitychange'));

      // Simulate time passing
      const oldTime = Date.now() - (AUTH_CHECK_CONFIG.INTERVAL + 1000);
      store.lastCheckTime = oldTime;

      console.log('Before visibility change:', {
        lastCheckTime: store.lastCheckTime,
        timeSinceLastCheck: Date.now() - store.lastCheckTime,
        needsCheck: store.needsCheck,
        visibilityState: document.visibilityState,
        handlerAttached: Boolean(store._visibilityHandler),
      });

      // Then make tab visible again
      Object.defineProperty(document, 'visibilityState', {
        configurable: true,
        value: 'visible',
      });
      document.dispatchEvent(new Event('visibilitychange'));

      // Wait for any async operations
      await vi.runAllTimersAsync();

      console.log('After running timers:', {
        axiosGetCalls: vi.mocked(axios.get).mock.calls.length,
        lastCheckTime: store.lastCheckTime,
        isAuthenticated: store.isAuthenticated,
        timeSinceLastCheck: Date.now() - store.lastCheckTime,
        visibilityState: document.visibilityState,
      });

      // Verify the actual effects we care about
      expect(axios.get).toHaveBeenCalledWith(AUTH_CHECK_CONFIG.ENDPOINT);
      expect(store.lastCheckTime).toBeGreaterThan(oldTime);
      expect(store.isAuthenticated).toBe(true);

      // Cleanup
      vi.useRealTimers();
      vi.unstubAllGlobals();
    });

    it.skip('maintains sync between local and window state', async () => {
      // Initialize store and set up window mock
      // const store = useAuthStore();
      mockWindow = {
        authenticated: false,
        cust: null,
        setTimeout: vi.fn(),
        clearTimeout: vi.fn(),
      };
      vi.stubGlobal('window', mockWindow);

      // Set initial authenticated state
      store.isAuthenticated = true;

      // Mock successful auth check response
      vi.mocked(axios.get).mockResolvedValueOnce({
        data: {
          record: mockCustomer,
          details: { authenticated: true },
        },
      });

      // Perform auth check
      await store.checkAuthStatus();

      // Verify both store and window state are in sync
      expect(store.isAuthenticated).toBe(true);
      expect(store.customer).toEqual(mockCustomer);
      expect(window.authenticated).toBe(true);
      expect(window.cust).toEqual(mockCustomer);
    });

    // Add test for async refresh if needed
    it('can refresh initial state asynchronously', async () => {
      store.isAuthenticated = true;
      await store.refreshInitialState();
      expect(store.lastCheckTime).not.toBeNull();
    });

    it('sets up error handler correctly', () => {
      const store = useAuthStore();
      const api = createApi();

      store.setupErrorHandler(api);

      expect(store._errorHandler).not.toBeNull();
      expect(store._api).toEqual(api);
    });
  });

  it('should have $logout method available on the store', () => {
    const store = useAuthStore();
    expect(store.$logout).toBeDefined();
    expect(typeof store.$logout).toBe('function');
  });

  it('initializes with correct values', () => {
    const store = useAuthStore();
    expect(store.isAuthenticated).toBe(false);
    expect(store.customer).toBeUndefined();
  });

  it('handles auth check error', async () => {
    const store = useAuthStore();
    store.isAuthenticated = true; // Make sure we start authenticated
    const logoutSpy = vi.spyOn(store, '$logout');

    // Mock a generic error (not 401 or 403) with status 500
    const genericError = new AxiosError('Auth check failed');
    genericError.response = { status: 500 } as any;
    vi.mocked(axios.get).mockRejectedValue(genericError);

    // First failure
    await store.checkAuthStatus();
    expect(store.isAuthenticated).toBe(false);
    expect(store.failureCount).toBe(1);

    // Need to re-authenticate between checks
    store.isAuthenticated = true;

    // Second failure
    await store.checkAuthStatus();
    expect(store.failureCount).toBe(2);
    store.isAuthenticated = true;

    // Third failure - should trigger logout
    await store.checkAuthStatus();
    expect(store.failureCount).toBe(0); // We clear all state on logout

    // Now $logout should be called once after three failures
    expect(logoutSpy).toHaveBeenCalledTimes(1);

    // Reset the mock
    logoutSpy.mockReset();

    // Now test with a 401 error
    const unauthorizedError = new AxiosError('Unauthorized');
    unauthorizedError.response = { status: 401 } as any;
    vi.mocked(axios.get).mockRejectedValueOnce(unauthorizedError);

    store.isAuthenticated = true;
    await store.checkAuthStatus();

    // $logout should be called immediately for a 401 error
    expect(logoutSpy).toHaveBeenCalledTimes(1);
  });

  it('sets authenticated status', () => {
    const store = useAuthStore();
    store.isAuthenticated = true;
    expect(store.isAuthenticated).toBe(true);
  });

  it('sets customer', () => {
    const store = useAuthStore();
    store.customer = mockCustomer;
    expect(store.customer).toEqual(mockCustomer);
  });

  it('checks auth status', async () => {
    const store = useAuthStore();
    store.isAuthenticated = true;
    vi.mocked(axios.get).mockResolvedValueOnce({
      data: {
        record: mockCustomer,
        details: { authenticated: true },
      },
    });

    await store.checkAuthStatus();
    expect(store.isAuthenticated).toBe(true);
    expect(store.customer).toEqual(mockCustomer);
  });

  it('logs out correctly', () => {
    const store = useAuthStore();

    // Set up initial authenticated state
    store.isAuthenticated = true;
    store.customer = mockCustomer;

    // Verify initial state
    expect(store.isAuthenticated).toBe(true);
    expect(store.customer).toEqual(mockCustomer);

    // Call the logout method
    store.logout();

    // Verify that the auth state is reset
    expect(store.customer).toBeUndefined();
    expect(store.isAuthenticated).toBe(false);

    // Verify that the auth check interval is stopped
    expect(store.authCheckTimer).toBeNull();

    expect(store.$stopAuthCheck).toBeDefined();
  });

  it('clears session storage key after logout', () => {
    const authStore = useAuthStore();
    // Define a storage key for testing purposes
    const storageKey = 'test-auth-storage-key';

    // Verify that the session key is not already populated
    expect(sessionStorage.getItem(storageKey)).toBeNull();

    sessionStorage.setItem(storageKey, '!');

    // Verify that the session key has the value we set
    expect(sessionStorage.getItem(storageKey)).toBe('!');

    // Simulate a logout
    authStore.logout();

    // Verify that the session storage key is cleared after logout
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('schedules and cancels auth checks correctly', () => {
    const store = useAuthStore();
    store.isAuthenticated = true;

    const checkAuthStatusSpy = vi.spyOn(store, 'checkAuthStatus');

    store.$scheduleNextCheck();
    expect(store.authCheckTimer).not.toBeNull();

    // Check timing within expected range
    const nextCallTime = vi.getTimerCount();
    expect(nextCallTime).toBeGreaterThanOrEqual(15 * 60 * 1000 - 90 * 1000); // min
    expect(nextCallTime).toBeLessThanOrEqual(15 * 60 * 1000 + 90 * 1000); // max

    store.$stopAuthCheck();
    expect(store.authCheckTimer).toBeNull();

    // Advance time - should not trigger check
    vi.advanceTimersByTime(20 * 60 * 1000);
    expect(checkAuthStatusSpy).not.toHaveBeenCalled();
  });

  describe('Getters', () => {
    it('needs check when never checked before', () => {
      const store = useAuthStore();
      expect(store.lastCheckTime).toBeNull();
      expect(store.needsCheck).toBe(true);
    });

    it('correctly determines if check is needed based on last check time', () => {
      const store = useAuthStore();

      // Simulate successful check
      store.lastCheckTime = Date.now();
      expect(store.needsCheck).toBe(false);

      // Simulate old check
      store.lastCheckTime = Date.now() - (AUTH_CHECK_CONFIG.INTERVAL + 1000);
      expect(store.needsCheck).toBe(true);
    });
  });

  describe('Cleanup', () => {
    it('properly cleans up resources on destruction', () => {
      const store = useAuthStore();
      const clearTimeoutSpy = vi.spyOn(window, 'clearTimeout');

      store.$scheduleNextCheck();
      store.$dispose();

      expect(clearTimeoutSpy).toHaveBeenCalled();
      expect(store.authCheckTimer).toBeNull();
    });

    it('removes visibility change listener on cleanup', () => {
      const store = useAuthStore();
      const removeEventListenerSpy = vi.spyOn(document, 'removeEventListener');

      store.initialize();
      store.$dispose();

      expect(removeEventListenerSpy).toHaveBeenCalledWith(
        'visibilitychange',
        expect.any(Function)
      );
    });
  });

  describe('State transitions', () => {
    it('maintains correct state during auth check lifecycle', async () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      const checkPromise = store.checkAuthStatus();
      expect(store.isCheckingAuth).toBe(true);

      await checkPromise;
      expect(store.isCheckingAuth).toBe(false);
    });

    it('properly initializes and tracks failures from null state', async () => {
      const store = useAuthStore();
      expect(store.failureCount).toBeNull(); // Initial state

      // Mock a failure
      vi.mocked(axios.get).mockRejectedValueOnce(new Error('Auth failed'));
      await store.checkAuthStatus();
      expect(store.failureCount).toBe(1); // First failure

      // Mock another failure
      await store.checkAuthStatus();
      expect(store.failureCount).toBe(2);

      // Mock success
      vi.mocked(axios.get).mockResolvedValueOnce({
        data: {
          record: mockCustomer,
          details: { authenticated: true },
        },
      });
      await store.checkAuthStatus();
      expect(store.failureCount).toBe(0); // Reset on success
    });
  });

  describe('Weirdness', () => {
    it('handles concurrent auth checks correctly', async () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      const check1 = store.checkAuthStatus();
      const check2 = store.checkAuthStatus();

      await Promise.all([check1, check2]);
      expect(store.isCheckingAuth).toBe(false);
    });
    it('handles network timeouts appropriately', async () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      vi.mocked(axios.get).mockImplementationOnce(
        () =>
          new Promise((_, reject) =>
            setTimeout(() => reject(new Error('Network timeout')), 5000)
          )
      );

      await store.checkAuthStatus();
      expect(store.failureCount).toBe(1);
    });
    it('schedules and cancels auth checks correctly', () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      const checkAuthStatusSpy = vi.spyOn(store, 'checkAuthStatus');

      // Use the actual constants from AUTH_CHECK_CONFIG
      const baseInterval = AUTH_CHECK_CONFIG.INTERVAL;
      const maxJitter = AUTH_CHECK_CONFIG.JITTER;

      store.$scheduleNextCheck();

      // Verify timer was set within expected range
      const nextCallTime = vi.getTimerCount();
      expect(nextCallTime).toBeGreaterThanOrEqual(baseInterval - maxJitter);
      expect(nextCallTime).toBeLessThanOrEqual(baseInterval + maxJitter);
    });
  });

  describe('Error handling', () => {
    it('handles auth errors according to new "3 strikes" policy', async () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      const error = new Error('Auth failed');
      vi.mocked(axios.get).mockRejectedValue(error);

      const logoutSpy = vi.spyOn(store, 'logout');

      // First two failures
      await store.checkAuthStatus();
      await store.checkAuthStatus();
      expect(store.failureCount).toBe(2);
      expect(logoutSpy).not.toHaveBeenCalled();

      // Third failure should trigger logout
      await store.checkAuthStatus();
      expect(logoutSpy).toHaveBeenCalledTimes(1);
      expect(store.failureCount).toBe(0); // Reset after logout
    });

    it('properly integrates with error handler', async () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      const errorHandlerSpy = vi.spyOn(store._errorHandler!, 'withErrorHandling');
      const error = new Error('Network error');
      vi.mocked(axios.get).mockRejectedValueOnce(error);

      await store.checkAuthStatus();

      expect(errorHandlerSpy).toHaveBeenCalled();
      expect(store.error).not.toBeNull();
      expect(store.isLoading).toBe(false);
    });

    it('properly initializes error handler with custom options', () => {
      const store = useAuthStore();
      const customNotify = vi.fn();
      const customLog = vi.fn();

      store.setupErrorHandler(createApi(), {
        notify: customNotify,
        log: customLog,
      });

      // Trigger an error
      store.checkAuthStatus();

      expect(customNotify).toHaveBeenCalled();
      expect(customLog).toHaveBeenCalled();
    });
  });

  describe('Extended', () => {
    // ... existing setup ...

    it('schedules next check with jitter', () => {
      const store = useAuthStore();
      store.isAuthenticated = true;

      const scheduleCheckSpy = vi.spyOn(store, '$scheduleNextCheck');
      store.$scheduleNextCheck();

      // Verify timer was set
      expect(store.authCheckTimer).not.toBeNull();

      // Verify timing is within expected range
      const baseInterval = 15 * 60 * 1000; // 15 minutes
      const maxJitter = 90 * 1000; // 90 seconds

      // Advance time and check if callback executed
      vi.advanceTimersByTime(baseInterval + maxJitter);
      expect(scheduleCheckSpy).toHaveBeenCalledTimes(2); // Initial + rescheduled
    });

    it('tracks lastCheckTime correctly', async () => {
      const store = useAuthStore();
      // in the `checkAuthStatus` method, there's an early return if not authenticated
      store.isAuthenticated = true; // Add this line
      const initialTime = Date.now();

      vi.mocked(axios.get).mockResolvedValueOnce({
        data: {
          record: mockCustomer,
          details: { authenticated: true },
        },
      });

      await store.checkAuthStatus();

      expect(store.lastCheckTime).not.toBeNull();
      expect(store.lastCheckTime!).toBeGreaterThanOrEqual(initialTime);
      expect(store.lastCheckTime!).toBeLessThanOrEqual(Date.now());
    });

    it('determines need for check based on elapsed time', () => {
      const store = useAuthStore();
      store.lastCheckTime = Date.now() - 16 * 60 * 1000; // 16 minutes ago

      expect(store.needsCheck).toBe(true);

      store.lastCheckTime = Date.now() - 14 * 60 * 1000; // 14 minutes ago
      expect(store.needsCheck).toBe(false);
    });

    it('handles visibility changes with proper timing', async () => {
      store.isAuthenticated = true;
      store.lastCheckTime = Date.now() - 16 * 60 * 1000;

      const checkAuthSpy = vi.spyOn(store, 'checkAuthStatus');

      // Simulate visibility change
      vi.stubGlobal('document', {
        ...document,
        visibilityState: 'visible',
      });
      document.dispatchEvent(new Event('visibilitychange'));

      expect(checkAuthSpy).toHaveBeenCalled();

      vi.unstubAllGlobals();
    });
  });

  describe('Auth Store Extended Behaviors', () => {
    let pinia: Pinia;
    let store: ReturnType<typeof useAuthStore>;

    beforeEach(() => {
      // Create fresh pinia instance
      pinia = createPinia();
      pinia.use(logoutPlugin);

      // Ensure clean setup
      setActivePinia(pinia);
      store = useAuthStore();
    });

    it('applies random jitter to auth check interval', () => {
      const checkTimes: number[] = [];

      // Mock the setTimeout to capture timing
      const originalSetTimeout = globalThis.setTimeout;
      const setTimeoutSpy = vi.fn((callback, delay) => {
        checkTimes.push(delay);
        return originalSetTimeout(callback, delay);
      });
      vi.stubGlobal('setTimeout', setTimeoutSpy);

      // Run multiple schedules to sample jitter distribution
      store.isAuthenticated = true;
      for (let i = 0; i < 10; i++) {
        store.$scheduleNextCheck();
      }

      // Validate jitter
      const baseInterval = 15 * 60 * 1000;
      const maxJitter = 90 * 1000;

      checkTimes.forEach((delay) => {
        expect(delay).toBeGreaterThanOrEqual(baseInterval - maxJitter);
        expect(delay).toBeLessThanOrEqual(baseInterval + maxJitter);
      });

      // Restore globalThis setTimeout
      vi.unstubAllGlobals();
    });

    it('tracks last check time accurately', async () => {
      const initialTime = Date.now();

      // Mock successful auth check
      vi.mocked(axios.get).mockResolvedValueOnce({
        data: {
          record: mockCustomer,
          details: { authenticated: true },
        },
      });

      await store.checkAuthStatus();

      expect(store.lastCheckTime).toBeGreaterThanOrEqual(initialTime);
      expect(store.lastCheckTime).toBeLessThanOrEqual(Date.now());
    });

    it('determines need for check based on elapsed time', () => {
      // Simulate different elapsed times
      store.lastCheckTime = Date.now() - 16 * 60 * 1000; // 16 minutes
      expect(store.needsCheck).toBe(true);

      store.lastCheckTime = Date.now() - 14 * 60 * 1000; // 14 minutes
      expect(store.needsCheck).toBe(false);
    });

    it('handles visibility change correctly', async () => {
      store.isAuthenticated = true;
      store.lastCheckTime = Date.now() - 16 * 60 * 1000;

      const checkAuthSpy = vi.spyOn(store, 'checkAuthStatus');

      // Simulate visibility change
      const visibilityChangeEvent = new Event('visibilitychange');
      Object.defineProperty(document, 'visibilityState', {
        value: 'visible',
        configurable: true,
      });
      document.dispatchEvent(visibilityChangeEvent);

      // Wait for potential async operations
      await vi.runAllTimersAsync();

      expect(checkAuthSpy).toHaveBeenCalledTimes(1);
    });

    it('manages authentication failures correctly', async () => {
      store.isAuthenticated = true;

      // Mock consecutive failures
      const failureError = new AxiosError('Auth check failed');
      failureError.response = { status: 500 } as any;
      vi.mocked(axios.get).mockRejectedValue(failureError);

      const logoutSpy = vi.spyOn(store, 'logout');

      // Simulate multiple failed checks
      for (let i = 0; i < 3; i++) {
        await store.checkAuthStatus();
      }

      // Verify logout triggered after 3 failures
      expect(logoutSpy).toHaveBeenCalledTimes(1);
      expect(store.failureCount).toBeNull();
    });
  });
});
