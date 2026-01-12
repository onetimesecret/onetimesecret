// src/tests/setup-bootstrap.ts
//
// Test utilities for WindowService/bootstrap state mocking.
// Consolidates 4 distinct mock patterns into a unified approach using
// createTestingPinia and typed fixtures.

import { vi } from 'vitest';
import { createTestingPinia, type TestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import type { OnetimeWindow } from '@/types/declarations/window';
import type { Customer } from '@/schemas/models';

// ============================================================================
// FIXTURES: Pre-configured bootstrap states for common test scenarios
// ============================================================================

/**
 * Base fixture with sensible defaults for all OnetimeWindow properties.
 * Use this as a foundation and override specific properties as needed.
 */
export const baseBootstrap: OnetimeWindow = {
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
export const authenticatedBootstrap: OnetimeWindow = {
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
export const anonymousBootstrap: OnetimeWindow = {
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
export const mfaPendingBootstrap: OnetimeWindow = {
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
export const colonelBootstrap: OnetimeWindow = {
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
export const customDomainsBootstrap: OnetimeWindow = {
  ...authenticatedBootstrap,
  domains_enabled: true,
  custom_domains: ['acme.example.com', 'widgets.example.com'],
};

/**
 * Billing disabled bootstrap state (standalone mode).
 * For testing self-hosted/standalone deployments.
 */
export const standaloneBootstrap: OnetimeWindow = {
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
  initialState?: Partial<OnetimeWindow>;
  /** Base fixture to extend from (defaults to baseBootstrap) */
  baseFixture?: OnetimeWindow;
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
  /** Current window state (mutable for test manipulation) */
  windowState: OnetimeWindow;
  /** WindowService mock with get/getMultiple/getState implementations */
  windowServiceMock: {
    get: ReturnType<typeof vi.fn>;
    getMultiple: ReturnType<typeof vi.fn>;
    getState: ReturnType<typeof vi.fn>;
    update: ReturnType<typeof vi.fn>;
  };
  /** Update window state mid-test */
  updateState: (updates: Partial<OnetimeWindow>) => void;
}

/**
 * Creates a test environment with mocked WindowService and Pinia.
 *
 * This is the recommended approach for tests that depend on bootstrap state.
 * It replaces the 4 distinct mock patterns with a unified, type-safe approach.
 *
 * @example
 * ```ts
 * // Basic anonymous user test
 * const { pinia, windowServiceMock } = setupBootstrapMock();
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
export function setupBootstrapMock(
  options: BootstrapMockOptions = {}
): BootstrapMockResult {
  const {
    initialState = {},
    baseFixture = baseBootstrap,
    stubActions = false,
    createSpy = vi.fn,
  } = options;

  // Merge base fixture with initial state
  const windowState: OnetimeWindow = {
    ...baseFixture,
    ...initialState,
  } as OnetimeWindow;

  // Create WindowService mock functions
  const getMock = createSpy((key: keyof OnetimeWindow) => {
    return windowState[key];
  });

  const getMultipleMock = createSpy(
    <K extends keyof OnetimeWindow>(
      input: K[] | Partial<Record<K, OnetimeWindow[K]>>
    ): Pick<OnetimeWindow, K> => {
      if (Array.isArray(input)) {
        return Object.fromEntries(
          input.map((key) => [key, windowState[key]])
        ) as Pick<OnetimeWindow, K>;
      }
      return Object.fromEntries(
        Object.entries(input).map(([key, defaultValue]) => [
          key,
          windowState[key as K] ?? defaultValue,
        ])
      ) as Pick<OnetimeWindow, K>;
    }
  );

  const getStateMock = createSpy(() => windowState);

  const updateMock = createSpy((updates: Partial<OnetimeWindow>) => {
    Object.assign(windowState, updates);
  });

  const windowServiceMock = {
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
  (window as any).__BOOTSTRAP_STATE__ = windowState;

  // Helper to update state mid-test
  const updateState = (updates: Partial<OnetimeWindow>) => {
    Object.assign(windowState, updates);
    // Also update window object for direct access
    (window as any).__BOOTSTRAP_STATE__ = windowState;
  };

  return {
    pinia,
    windowState,
    windowServiceMock,
    updateState,
  };
}

/**
 * Creates a WindowService mock for use with vi.mock().
 *
 * Use this when you need to mock WindowService at the module level
 * (in vi.mock() calls before imports).
 *
 * @example
 * ```ts
 * // At top of test file, before imports
 * const { mockGet, mockGetMultiple } = vi.hoisted(() =>
 *   createHoistedWindowServiceMock()
 * );
 *
 * vi.mock('@/services/window.service', () => ({
 *   WindowService: {
 *     get: mockGet,
 *     getMultiple: mockGetMultiple,
 *   },
 * }));
 *
 * // In test
 * mockGet.mockImplementation((key) => {
 *   if (key === 'authenticated') return true;
 *   return undefined;
 * });
 * ```
 */
export function createHoistedWindowServiceMock() {
  return {
    mockGet: vi.fn(),
    mockGetMultiple: vi.fn(),
    mockGetState: vi.fn(() => ({})),
    mockUpdate: vi.fn(),
  };
}

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
 * vi.spyOn(WindowService, 'get').mockImplementation((key) =>
 *   override[key] ?? baseBootstrap[key]
 * );
 * ```
 */
export function createStateOverride(
  overrides: Partial<OnetimeWindow>
): Partial<OnetimeWindow> {
  return { ...overrides };
}

// ============================================================================
// DOCUMENTATION: The 4 Mock Patterns Found in Existing Tests
// ============================================================================

/**
 * ## Pattern 1: vi.spyOn with per-key implementation
 *
 * Found in: DashboardBasic.spec.ts, languageStore.spec.ts, UserMenu.spec.ts
 *
 * ```ts
 * vi.spyOn(WindowService, 'get').mockImplementation((key: string) => {
 *   if (key === 'cust') return { feature_flags: { beta: false } };
 *   if (key === 'billing_enabled') return true;
 *   return undefined;
 * });
 * ```
 *
 * Migration:
 * ```ts
 * const { windowServiceMock } = setupBootstrapMock({
 *   initialState: {
 *     cust: { ...mockCustomer, feature_flags: { beta: false } },
 *     billing_enabled: true,
 *   },
 * });
 * vi.spyOn(WindowService, 'get').mockImplementation(windowServiceMock.get);
 * ```
 *
 * ## Pattern 2: vi.hoisted with vi.mock at module level
 *
 * Found in: useEntitlements.spec.ts
 *
 * ```ts
 * const { mockWindowGet } = vi.hoisted(() => ({
 *   mockWindowGet: vi.fn(),
 * }));
 *
 * vi.mock('@/services/window.service', () => ({
 *   WindowService: { get: mockWindowGet },
 * }));
 * ```
 *
 * Migration:
 * ```ts
 * const { mockGet } = vi.hoisted(() => createHoistedWindowServiceMock());
 *
 * vi.mock('@/services/window.service', () => ({
 *   WindowService: { get: mockGet },
 * }));
 *
 * // In beforeEach
 * const { windowState } = setupBootstrapMock({ initialState: authenticatedBootstrap });
 * mockGet.mockImplementation((key) => windowState[key]);
 * ```
 *
 * ## Pattern 3: Full module mock with static values
 *
 * Found in: useDomainScope.spec.ts, useSecretContext.spec.ts
 *
 * ```ts
 * vi.mock('@/services/window.service', () => ({
 *   WindowService: {
 *     get: vi.fn((key: string) => {
 *       const mockState = { domain_strategy: 'canonical', ... };
 *       return mockState[key];
 *     }),
 *     getMultiple: vi.fn(),
 *   },
 * }));
 * ```
 *
 * Migration:
 * ```ts
 * const { mockGet, mockGetMultiple } = vi.hoisted(() =>
 *   createHoistedWindowServiceMock()
 * );
 *
 * vi.mock('@/services/window.service', () => ({
 *   WindowService: { get: mockGet, getMultiple: mockGetMultiple },
 * }));
 *
 * // In beforeEach
 * const { windowState } = setupBootstrapMock({
 *   initialState: {
 *     domain_strategy: 'canonical',
 *     domains_enabled: true,
 *     ...
 *   },
 * });
 * mockGet.mockImplementation((key) => windowState[key]);
 * mockGetMultiple.mockImplementation((input) => { ... });
 * ```
 *
 * ## Pattern 4: vi.mocked with dynamic return values
 *
 * Found in: useDomainScope.spec.ts (for getMultiple)
 *
 * ```ts
 * vi.mocked(WindowService.getMultiple).mockReturnValue({
 *   domains_enabled: true,
 *   site_host: 'onetimesecret.com',
 * });
 * ```
 *
 * Migration:
 * ```ts
 * const { updateState, windowServiceMock } = setupBootstrapMock({
 *   initialState: customDomainsBootstrap,
 * });
 * vi.spyOn(WindowService, 'getMultiple').mockImplementation(
 *   windowServiceMock.getMultiple
 * );
 *
 * // Update dynamically in test
 * updateState({ domains_enabled: true, site_host: 'onetimesecret.com' });
 * ```
 */
