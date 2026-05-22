// src/tests/components/ShowSecretCapabilities.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { RouteLocationNormalized } from 'vue-router';

// Import the routes to test the beforeEnter guard
import secretRoutes from '@/apps/secret/routes/secret';

/**
 * Creates a mock route location for testing route guards.
 */
const createMockRoute = (secretIdentifier: string): RouteLocationNormalized => ({
  params: { secretIdentifier },
  path: `/secret/${secretIdentifier}`,
  name: 'Secret link',
  matched: [],
  fullPath: `/secret/${secretIdentifier}`,
  query: {},
  hash: '',
  redirectedFrom: undefined,
  meta: {},
});

/**
 * Sets up the testing pinia with the specified show capability value.
 */
const setupPinia = (showCapability: boolean | undefined) => {
  const capabilities =
    showCapability === undefined ? {} : { show: showCapability };

  return createTestingPinia({
    createSpy: vi.fn,
    initialState: {
      bootstrap: {
        ui: { capabilities },
      },
    },
  });
};

describe('Secret route - show capability gating', () => {
  const secretRoute = secretRoutes[0];
  const beforeEnter = secretRoute.beforeEnter as (
    to: RouteLocationNormalized
  ) => { name: string } | undefined;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('redirects to NotFound when ui.capabilities.show is false', () => {
    setupPinia(false);
    const mockRoute = createMockRoute('abc123');

    const result = beforeEnter(mockRoute);

    expect(result).toEqual({ name: 'NotFound' });
  });

  it('allows navigation when ui.capabilities.show is true', () => {
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

  it('redirects to NotFound for invalid secretIdentifier regardless of capability', () => {
    setupPinia(true);
    const mockRoute = createMockRoute('invalid-key!');

    const result = beforeEnter(mockRoute);

    expect(result).toEqual({ name: 'NotFound' });
  });

  it('validates secretIdentifier before checking capability (short-circuits)', () => {
    // When key is invalid, should redirect without checking capability
    setupPinia(false);
    const mockRoute = createMockRoute('');

    const result = beforeEnter(mockRoute);

    expect(result).toEqual({ name: 'NotFound' });
  });
});
