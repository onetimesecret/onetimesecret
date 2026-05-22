// src/tests/components/ShowReceiptRouteCapabilities.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { RouteLocationNormalized } from 'vue-router';

// Import the routes to test the beforeEnter guard
import receiptRoutes from '@/apps/secret/routes/receipt';

/**
 * Creates a mock route location for testing route guards.
 */
const createMockRoute = (receiptIdentifier: string): RouteLocationNormalized => ({
  params: { receiptIdentifier },
  path: `/receipt/${receiptIdentifier}`,
  name: 'Receipt link',
  matched: [],
  fullPath: `/receipt/${receiptIdentifier}`,
  query: {},
  hash: '',
  redirectedFrom: undefined,
  meta: {},
});

/**
 * Sets up the testing pinia with the specified receipt capability value.
 */
const setupPinia = (receiptCapability: boolean | undefined) => {
  const capabilities =
    receiptCapability === undefined ? {} : { receipt: receiptCapability };

  return createTestingPinia({
    createSpy: vi.fn,
    initialState: {
      bootstrap: {
        ui: { capabilities },
      },
    },
  });
};

describe('Receipt route - receipt capability gating', () => {
  const receiptRoute = receiptRoutes[0];
  const beforeEnter = receiptRoute.beforeEnter as (
    to: RouteLocationNormalized
  ) => { name: string } | undefined;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('redirects to NotFound when ui.capabilities.receipt is false', () => {
    setupPinia(false);
    const mockRoute = createMockRoute('abc123');

    const result = beforeEnter(mockRoute);

    expect(result).toEqual({ name: 'NotFound' });
  });

  it('allows navigation when ui.capabilities.receipt is true', () => {
    setupPinia(true);
    const mockRoute = createMockRoute('abc123');

    const result = beforeEnter(mockRoute);

    expect(result).toBeUndefined();
  });

  it('allows navigation when the capability flag is unset (default enabled)', () => {
    setupPinia(undefined);
    const mockRoute = createMockRoute('abc123');

    const result = beforeEnter(mockRoute);

    expect(result).toBeUndefined();
  });

  it('redirects to NotFound for invalid receiptIdentifier regardless of capability', () => {
    setupPinia(true);
    const mockRoute = createMockRoute('invalid-key!');

    const result = beforeEnter(mockRoute);

    expect(result).toEqual({ name: 'NotFound' });
  });

  it('validates receiptIdentifier before checking capability (short-circuits)', () => {
    // When key is invalid, should redirect without checking capability
    setupPinia(false);
    const mockRoute = createMockRoute('');

    const result = beforeEnter(mockRoute);

    expect(result).toEqual({ name: 'NotFound' });
  });
});
