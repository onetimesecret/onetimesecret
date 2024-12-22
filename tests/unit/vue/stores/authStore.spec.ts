import { logoutPlugin } from '@/plugins/pinia/logoutPlugin';
import { Customer, Plan } from '@/schemas/models';
import { useAuthStore } from '@/stores/authStore';
import axios, { AxiosError } from 'axios';
import { createPinia, Pinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from 'vue';
import { Router, useRouter } from 'vue-router';
import { setupRouter } from '../utils/routerSetup';

vi.mock('axios');
// Mock the api module
vi.mock('@/utils/api', () => ({
  default: {
    post: vi.fn(),
  },
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
  created: new Date('2023-05-20T00:00:00Z'),
  updated: new Date('2023-05-20T00:00:00Z'),
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

describe('Auth Store', () => {
  let router: Router;
  let pinia: Pinia;
  let store: ReturnType<typeof useAuthStore>;

  beforeEach(() => {
    const app = createApp({});
    pinia = createPinia();
    pinia.use(logoutPlugin);
    app.use(pinia);
    setActivePinia(pinia);

    // Initialize the store after pinia is set up
    store = useAuthStore();

    vi.useFakeTimers();

    // Setup the router. This mimics what happens in main.ts
    router = setupRouter();
    vi.mocked(useRouter).mockReturnValue(router);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
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
    store.setAuthenticated(true); // Make sure we start authenticated
    const logoutSpy = vi.spyOn(store, '$logout');

    // Mock a generic error (not 401 or 403) with status 500
    const genericError = new AxiosError('Auth check failed');
    genericError.response = { status: 500 } as any;
    vi.mocked(axios.get).mockRejectedValue(genericError);

    // First failure
    await store.checkAuthStatus();
    expect(store.isAuthenticated).toBe(false);
    expect(store.failedAuthChecks).toBe(1);

    // Need to re-authenticate between checks
    store.setAuthenticated(true);

    // Second failure
    await store.checkAuthStatus();
    expect(store.failedAuthChecks).toBe(2);
    store.setAuthenticated(true);

    // Third failure - should trigger logout
    await store.checkAuthStatus();
    expect(store.failedAuthChecks).toBe(0); // We clear all state on logout

    // Now $logout should be called once after three failures
    expect(logoutSpy).toHaveBeenCalledTimes(1);

    // Reset the mock
    logoutSpy.mockReset();

    // Now test with a 401 error
    const unauthorizedError = new AxiosError('Unauthorized');
    unauthorizedError.response = { status: 401 } as any;
    vi.mocked(axios.get).mockRejectedValueOnce(unauthorizedError);

    store.setAuthenticated(true);
    await store.checkAuthStatus();

    // $logout should be called immediately for a 401 error
    expect(logoutSpy).toHaveBeenCalledTimes(1);
  });

  it('sets authenticated status', () => {
    const store = useAuthStore();
    store.setAuthenticated(true);
    expect(store.isAuthenticated).toBe(true);
  });

  it('sets customer', () => {
    const store = useAuthStore();
    store.setCustomer(mockCustomer);
    expect(store.customer).toEqual(mockCustomer);
  });

  it('checks auth status', async () => {
    const store = useAuthStore();
    store.setAuthenticated(true);
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
    store.setAuthenticated(true);
    store.setCustomer(mockCustomer);

    // Verify initial state
    expect(store.isAuthenticated).toBe(true);
    expect(store.customer).toEqual(mockCustomer);

    // Call the logout method
    store.logout();

    // Verify that the auth state is reset
    expect(store.customer).toBeUndefined();
    expect(store.isAuthenticated).toBe(false);

    // Verify that the auth check interval is stopped
    expect(store.authCheckInterval).toBeNull();
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

  it('starts auth check interval', () => {
    const store = useAuthStore();
    const checkAuthStatusSpy = vi.spyOn(store, 'checkAuthStatus');
    const startAuthCheckSpy = vi.spyOn(store, 'startAuthCheck');

    store.startAuthCheck();
    expect(startAuthCheckSpy).toHaveBeenCalled();

    // Advance time by the maximum possible interval (MAX_AUTH_CHECK_INTERVAL_MS + 90 seconds)
    vi.advanceTimersByTime(60 * 60 * 1000 + 90 * 1000);

    expect(checkAuthStatusSpy).toHaveBeenCalled();
  });

  it('stops auth check interval', () => {
    const store = useAuthStore();
    store.startAuthCheck();
    store.stopAuthCheck();

    const checkAuthStatusSpy = vi.spyOn(store, 'checkAuthStatus');
    vi.advanceTimersByTime(30 * 60 * 1000); // fast forward

    expect(checkAuthStatusSpy).not.toHaveBeenCalled();
  });

  it('initializes correctly', () => {
    const store = useAuthStore();
    const setupAxiosInterceptorSpy = vi.spyOn(store, 'setupAxiosInterceptor');

    vi.stubGlobal('authenticated', true);
    vi.stubGlobal('cust', mockCustomer);

    store.initialize();

    expect(store.isAuthenticated).toBe(true);
    expect(store.customer).toEqual(mockCustomer);
    expect(setupAxiosInterceptorSpy).toHaveBeenCalled();

    vi.unstubAllGlobals();
  });

  it('sets up axios interceptor', () => {
    const store = useAuthStore();
    const interceptorSpy = vi.spyOn(axios.interceptors.response, 'use');

    store.setupAxiosInterceptor();

    expect(interceptorSpy).toHaveBeenCalled();
  });
});
