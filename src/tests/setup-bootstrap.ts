// src/tests/setup-bootstrap.ts
//
// Test utilities for bootstrap state mocking.
// Provides a unified approach using createTestingPinia and typed fixtures.

import type { Customer } from '@/schemas/models';
import type { BootstrapPayload } from '@/types/declarations/bootstrap';
import { createTestingPinia, type TestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { vi } from 'vitest';

// ============================================================================
// FIXTURES: Pre-configured bootstrap states for common test scenarios
// ============================================================================

/**
 * Base fixture with sensible defaults for all BootstrapPayload properties.
 * Use this as a foundation and override specific properties as needed.
 */
export const baseBootstrap: BootstrapPayload = {
  authenticated: false,
  awaiting_mfa: false,
  had_valid_session: false,
  baseuri: 'https://test.onetimesecret.com',
  cust: null,
  custid: '',
  domains_enabled: false,
  email: '',
  frontend_host: 'https://test.onetimesecret.com',

  // i18n
  i18n_enabled: true,
  locale: 'en',
  supported_locales: ['en', 'es', 'fr', 'de'],
  fallback_locale: 'en',
  default_locale: 'en',

  // Version info
  ot_version: '0.20.0',
  ot_version_long: '0.20.0 (test)',
  ruby_version: 'ruby-335',

  // Feature flags
  billing_enabled: true,
  regions_enabled: false,

  // Security
  shrimp: 'test-csrf-token',

  // Domain configuration
  site_host: 'test.onetimesecret.com',
  canonical_domain: 'test.onetimesecret.com',
  domain_strategy: 'canonical',
  domain_id: '',
  display_domain: 'test.onetimesecret.com',
  domain_branding: {
    allow_public_homepage: false,
    button_text_light: true,
    corner_style: 'rounded',
    font_family: 'sans',
    instructions_post_reveal: '',
    instructions_pre_reveal: '',
    instructions_reveal: '',
    primary_color: '#36454F',
  },
  domain_logo: null,

  // Authentication settings
  authentication: {
    enabled: true,
    signup: true,
    signin: true,
    autoverify: false,
    required: false,
    mode: 'simple',
  },

  // Secret options
  secret_options: {
    default_ttl: 604800.0,
    ttl_options: [60, 3600, 86400, 604800, 1209600, 2592000],
  },

  // Regions
  regions: {
    identifier: 'US',
    enabled: false,
    current_jurisdiction: 'US',
    jurisdictions: [],
  },
  available_jurisdictions: ['US'],

  // UI
  enjoyTheVue: true,
  messages: [],
  d9s_enabled: false,
  diagnostics: {
    sentry: {
      enabled: false,
      dsn: '',
      logErrors: true,
      trackComponents: true,
    },
  },
  features: {
    markdown: true,
  },
  ui: {
    enabled: true,
  },
};

/**
 * Customer fixture for authenticated states.
 */
export const mockCustomer: Customer = {
  identifier: 'cust_ext_123',
  objid: 'cust_obj_123',
  extid: 'cust_ext_123',
  email: 'test@example.com',
  role: 'customer',
  verified: true,
  created: new Date(),
  updated: new Date(),
  feature_flags: { beta: false },
  secrets_created: 10,
  secrets_burned: 2,
  secrets_shared: 5,
  emails_sent: 3,
  active: true,
  locale: 'en',
  last_login: null,
  notify_on_reveal: false,
};

/**
 * Authenticated user bootstrap state.
 * User is fully authenticated with customer data.
 */
export const authenticatedBootstrap: BootstrapPayload = {
  ...baseBootstrap,
  authenticated: true,
  awaiting_mfa: false,
  had_valid_session: true,
  cust: mockCustomer,
  custid: mockCustomer.extid,
  email: mockCustomer.email,
};

/**
 * Anonymous user bootstrap state.
 * User is not authenticated, no customer data.
 */
export const anonymousBootstrap: BootstrapPayload = {
  ...baseBootstrap,
  authenticated: false,
  awaiting_mfa: false,
  had_valid_session: false,
  cust: null,
  custid: '',
  email: '',
};

/**
 * MFA pending bootstrap state.
 * User has passed first factor but needs to complete MFA.
 */
export const mfaPendingBootstrap: BootstrapPayload = {
  ...baseBootstrap,
  authenticated: false,
  awaiting_mfa: true,
  had_valid_session: true,
  cust: mockCustomer,
  custid: mockCustomer.extid,
  email: mockCustomer.email,
};

/**
 * Colonel (admin) user bootstrap state.
 * Authenticated user with admin privileges and test mode capabilities.
 */
export const colonelBootstrap: BootstrapPayload = {
  ...authenticatedBootstrap,
  cust: {
    ...mockCustomer,
    role: 'colonel',
  },
  entitlement_test_planid: null,
  entitlement_test_plan_name: null,
  development: {
    enabled: true,
    domain_context_enabled: true,
  },
};

/**
 * Custom domains enabled bootstrap state.
 * Authenticated user with custom domain features enabled.
 */
export const customDomainsBootstrap: BootstrapPayload = {
  ...authenticatedBootstrap,
  domains_enabled: true,
  custom_domains: ['acme.example.com', 'widgets.example.com'],
};

/**
 * Billing disabled bootstrap state (standalone mode).
 * For testing self-hosted/standalone deployments.
 */
export const standaloneBootstrap: BootstrapPayload = {
  ...authenticatedBootstrap,
  billing_enabled: false,
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

  // Set up window.__BOOTSTRAP_STATE__ for components that access it directly
  (window as any).__BOOTSTRAP_STATE__ = bootstrapState;

  // Helper to update state mid-test
  const updateState = (updates: Partial<BootstrapPayload>) => {
    Object.assign(bootstrapState, updates);
    // Also update window object for direct access
    (window as any).__BOOTSTRAP_STATE__ = bootstrapState;
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
