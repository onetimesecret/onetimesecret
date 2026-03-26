// src/tests/setup-bootstrap.ts
//
// Test utilities for bootstrap state mocking.
// Provides a unified approach using createTestingPinia and typed fixtures.
//
// Fixtures are defined in fixtures/bootstrap.fixture.ts and re-exported here
// for backward compatibility.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { createTestingPinia, type TestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { vi } from 'vitest';

// Import and re-export fixtures for backward compatibility
import {
  mockCustomer,
  baseBootstrap,
  authenticatedBootstrap,
  anonymousBootstrap,
  mfaPendingBootstrap,
  colonelBootstrap,
  customDomainsBootstrap,
  standaloneBootstrap,
} from '@/tests/fixtures/bootstrap.fixture';

export {
  mockCustomer,
  baseBootstrap,
  authenticatedBootstrap,
  anonymousBootstrap,
  mfaPendingBootstrap,
  colonelBootstrap,
  customDomainsBootstrap,
  standaloneBootstrap,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Options for setupBootstrapMock.
 */
export interface BootstrapMockOptions {
  /** Initial bootstrap state (defaults to anonymousBootstrap) */
  initialState?: Partial<BootstrapPayload>;
  /** Base fixture to extend from (defaults to baseBootstrap) */
  baseFixture?: BootstrapPayload;
  /** Whether to stub Pinia actions (defaults to false) */
  stubActions?: boolean;
  /** Vitest spy function (defaults to vi.fn) */
  createSpy?: typeof vi.fn;
}

/**
 * Result from setupBootstrapMock.
 */
export interface BootstrapMockResult {
  /** The testing Pinia instance */
  pinia: TestingPinia;
  /** Current bootstrap state (mutable for test manipulation) */
  bootstrapState: BootstrapPayload;
  /** Bootstrap mock with get/getMultiple/getState implementations */
  bootstrapMock: {
    get: ReturnType<typeof vi.fn>;
    getMultiple: ReturnType<typeof vi.fn>;
    getState: ReturnType<typeof vi.fn>;
    update: ReturnType<typeof vi.fn>;
  };
  /** Update bootstrap state mid-test */
  updateState: (updates: Partial<BootstrapPayload>) => void;
}

/**
 * Creates a test environment with mocked bootstrap state and Pinia.
 *
 * This is the recommended approach for tests that depend on bootstrap state.
 * Provides a unified, type-safe approach for all test scenarios.
 *
 * @example
 * ```ts
 * // Basic anonymous user test
 * const { pinia, bootstrapMock } = setupBootstrapMock();
 *
 * // Authenticated user test
 * const { pinia } = setupBootstrapMock({
 *   initialState: authenticatedBootstrap,
 * });
 *
 * // Custom overrides
 * const { pinia, updateState } = setupBootstrapMock({
 *   initialState: {
 *     authenticated: true,
 *     billing_enabled: false,
 *     custom_domains: ['my.domain.com'],
 *   },
 * });
 *
 * // Update state mid-test
 * updateState({ authenticated: false });
 * ```
 */
export function setupBootstrapMock(options: BootstrapMockOptions = {}): BootstrapMockResult {
  const {
    initialState = {},
    baseFixture = baseBootstrap,
    stubActions = false,
    createSpy = vi.fn,
  } = options;

  // Merge base fixture with initial state
  const bootstrapState: BootstrapPayload = {
    ...baseFixture,
    ...initialState,
  } as BootstrapPayload;

  // Create bootstrap mock functions
  const getMock = createSpy((key: keyof BootstrapPayload) => {
    return bootstrapState[key];
  });

  const getMultipleMock = createSpy(
    <K extends keyof BootstrapPayload>(
      input: K[] | Partial<Record<K, BootstrapPayload[K]>>
    ): Pick<BootstrapPayload, K> => {
      if (Array.isArray(input)) {
        return Object.fromEntries(input.map((key) => [key, bootstrapState[key]])) as Pick<
          BootstrapPayload,
          K
        >;
      }
      return Object.fromEntries(
        Object.entries(input).map(([key, defaultValue]) => [
          key,
          bootstrapState[key as K] ?? defaultValue,
        ])
      ) as Pick<BootstrapPayload, K>;
    }
  );

  const getStateMock = createSpy(() => bootstrapState);

  const updateMock = createSpy((updates: Partial<BootstrapPayload>) => {
    Object.assign(bootstrapState, updates);
  });

  const bootstrapMock = {
    get: getMock,
    getMultiple: getMultipleMock,
    getState: getStateMock,
    update: updateMock,
  };

  // Create testing Pinia
  const pinia = createTestingPinia({
    stubActions,
    createSpy,
  });
  setActivePinia(pinia);

  // Set up window.__BOOTSTRAP_ME__ for components that access it directly
  (window as any).__BOOTSTRAP_ME__ = bootstrapState;

  // Helper to update state mid-test
  const updateState = (updates: Partial<BootstrapPayload>) => {
    Object.assign(bootstrapState, updates);
    // Also update window object for direct access
    (window as any).__BOOTSTRAP_ME__ = bootstrapState;
  };

  return {
    pinia,
    bootstrapState,
    bootstrapMock,
    updateState,
  };
}

/**
 * Creates a bootstrap mock for use with vi.hoisted().
 *
 * Use this when you need to create mocks at the module level
 * (in vi.hoisted() calls before imports).
 *
 * @example
 * ```ts
 * // At top of test file, before imports
 * const { mockGet, mockGetMultiple } = vi.hoisted(() =>
 *   createHoistedBootstrapMock()
 * );
 *
 * // In beforeEach
 * const { bootstrapState } = setupBootstrapMock({ initialState: authenticatedBootstrap });
 * mockGet.mockImplementation((key) => bootstrapState[key]);
 * ```
 */
export function createHoistedBootstrapMock() {
  return {
    mockGet: vi.fn(),
    mockGetMultiple: vi.fn(),
    mockGetState: vi.fn(() => ({})),
    mockUpdate: vi.fn(),
  };
}

/**
 * @deprecated Use createHoistedBootstrapMock instead
 */
export const createHoistedWindowServiceMock = createHoistedBootstrapMock;

/**
 * Convenience function to create a state override object for specific keys.
 *
 * @example
 * ```ts
 * const override = createStateOverride({
 *   authenticated: true,
 *   billing_enabled: false,
 * });
 *
 * const { bootstrapMock } = setupBootstrapMock({ initialState: override });
 * ```
 */
export function createStateOverride(
  overrides: Partial<BootstrapPayload>
): Partial<BootstrapPayload> {
  return { ...overrides };
}

// ============================================================================
// HISTORICAL REFERENCE: Legacy WindowService Mock Patterns
// ============================================================================
//
// NOTE: WindowService was removed in #2365. This documentation is preserved
// as historical reference for understanding legacy test patterns. All tests
// should now use setupBootstrapMock() directly with bootstrapStore.
//
// The recommended modern approach:
// ```ts
// const { pinia, bootstrapState, bootstrapMock, updateState } = setupBootstrapMock({
//   initialState: authenticatedBootstrap,
// });
// ```
