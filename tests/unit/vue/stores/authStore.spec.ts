import { useAuthStore } from '@/stores/authStore';
import { Customer, Plan } from '@/types/onetime';
import axios from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { Router, useRouter } from 'vue-router';
import { setupRouter } from '../utils/routerSetup';


vi.mock('axios')
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
  created: '2023-05-20T00:00:00Z',
  updated: '2023-05-20T00:00:00Z',
  planid: 'basic',
  price: 0,
  discount: 0,
  options: {
    ttl: 7 * 24 * 60 * 60, // 7 days in seconds
    size: 1024 * 1024, // 1MB in bytes
    api: false,
    name: 'Basic Plan',
  }
}

// Create a mock Customer object that matches the actual Customer type
const mockCustomer: Customer = {
  identifier: 'cust-1',
  custid: '1',
  role: 'user',
  planid: 'basic',
  plan: mockPlan,
  verified: 'true', // Changed to string
  updated: Date.now(),
  created: Date.now(),
  secrets_created: 0,
  active: 'true',
  locale: 'en-US',
  stripe_checkout_email: 'john@example.com',
  stripe_subscription_id: 'sub_123456',
  stripe_customer_id: 'cus_123456',
}

describe('Auth Store', () => {
  let router: Router;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.useFakeTimers();

    // Setup the router. This mimics what happens in main.ts
    router = setupRouter();
    vi.mocked(useRouter).mockReturnValue(router);
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it('initializes with correct values', () => {
    const store = useAuthStore()
    expect(store.isAuthenticated).toBe(false)
    expect(store.customer).toBeUndefined()
  })

  it('handles auth check error', async () => {
    const store = useAuthStore()
    vi.mocked(axios.get).mockRejectedValueOnce(new Error('Auth check failed'))

    await store.checkAuthStatus()
    expect(store.isAuthenticated).toBe(false)
    expect(store.customer).toBeUndefined()
    // router.push should not be called on the first failure
    expect(router.push).not.toHaveBeenCalled()

    // Simulate three consecutive failures
    await store.checkAuthStatus()
    await store.checkAuthStatus()
    await store.checkAuthStatus()

    // Now router.push should be called
    expect(router.push).toHaveBeenCalledWith('/signin')
  })


  it('sets authenticated status', () => {
    const store = useAuthStore()
    store.setAuthenticated(true)
    expect(store.isAuthenticated).toBe(true)
  })

  it('sets customer', () => {
    const store = useAuthStore()
    store.setCustomer(mockCustomer)
    expect(store.customer).toEqual(mockCustomer)
  })

  it('checks auth status', async () => {
    const store = useAuthStore()
    vi.mocked(axios.get).mockResolvedValueOnce({
      data: {
        details: { authorized: true },
        record: mockCustomer
      }
    })

    await store.checkAuthStatus()
    expect(store.isAuthenticated).toBe(true)
    expect(store.customer).toEqual(mockCustomer)
  })


  it('logs out correctly', () => {
    const store = useAuthStore();
    store.setAuthenticated(true);
    store.setCustomer(mockCustomer);

    store.logout();

    expect(store.isAuthenticated).toBe(false);
    expect(store.customer).toBeUndefined();
    expect(router.push).toHaveBeenCalledWith('/signin');
  });

  it('starts auth check interval', () => {
    const store = useAuthStore()
    const checkAuthStatusSpy = vi.spyOn(store, 'checkAuthStatus')
    const startAuthCheckSpy = vi.spyOn(store, 'startAuthCheck')

    store.startAuthCheck()
    expect(startAuthCheckSpy).toHaveBeenCalled()

    // Advance time by the maximum possible interval (MAX_AUTH_CHECK_INTERVAL_MS + 90 seconds)
    vi.advanceTimersByTime(60 * 60 * 1000 + 90 * 1000)

    expect(checkAuthStatusSpy).toHaveBeenCalled()
  })

  it('stops auth check interval', () => {
    const store = useAuthStore()
    store.startAuthCheck()
    store.stopAuthCheck()

    const checkAuthStatusSpy = vi.spyOn(store, 'checkAuthStatus')
    vi.advanceTimersByTime(30 * 60 * 1000) // fast forward

    expect(checkAuthStatusSpy).not.toHaveBeenCalled()
  })

  it('initializes correctly', () => {
    const store = useAuthStore()
    const setupAxiosInterceptorSpy = vi.spyOn(store, 'setupAxiosInterceptor')

    vi.stubGlobal('authenticated', true)
    vi.stubGlobal('cust', mockCustomer)

    store.initialize()

    expect(store.isAuthenticated).toBe(true)
    expect(store.customer).toEqual(mockCustomer)
    expect(setupAxiosInterceptorSpy).toHaveBeenCalled()

    vi.unstubAllGlobals()
  })

  it('sets up axios interceptor', () => {
    const store = useAuthStore()
    const interceptorSpy = vi.spyOn(axios.interceptors.response, 'use')

    store.setupAxiosInterceptor()

    expect(interceptorSpy).toHaveBeenCalled()
  })
})
