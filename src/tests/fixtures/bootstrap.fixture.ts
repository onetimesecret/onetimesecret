// src/tests/fixtures/bootstrap.fixture.ts
//
// Bootstrap payload fixtures for testing.
// These provide pre-configured states for common test scenarios.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import type { CustomerCanonical } from '@/schemas/contracts/customer';

// =============================================================================
// CUSTOMER FIXTURE
// =============================================================================

/**
 * Customer fixture for authenticated states.
 */
export const mockCustomer: CustomerCanonical = {
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

// =============================================================================
// BASE BOOTSTRAP FIXTURE
// =============================================================================

/**
 * Base fixture with sensible defaults for all BootstrapPayload properties.
 * Use this as a foundation and override specific properties as needed.
 *
 * This is the canonical test fixture — all scenario fixtures derive from it.
 */
export const baseBootstrap: BootstrapPayload = {
  // Authentication state
  authenticated: false,
  awaiting_mfa: false,
  had_valid_session: false,
  has_password: false,

  // User identity (empty for anonymous)
  cust: null,
  custid: '',
  email: '',
  customer_since: undefined,

  // API access (optional)
  apitoken: undefined,

  // URLs and hosts
  baseuri: 'https://test.onetimesecret.com',
  frontend_host: 'https://test.onetimesecret.com',
  site_host: 'test.onetimesecret.com',
  support_host: 'support.onetimesecret.com',

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
  domains_enabled: false,

  // Security
  shrimp: 'test-csrf-token',

  // Domain configuration
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
  domain_context: undefined,
  custom_domains: undefined,

  // Homepage mode (null = normal, 'external' | 'internal' for special modes)
  homepage_mode: undefined,

  // Global banner (optional HTML content)
  global_banner: undefined,

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

  // Development mode configuration (optional)
  development: undefined,

  // Organization (optional, only for authenticated users)
  organization: undefined,

  // Entitlement testing (colonel only)
  entitlement_test_planid: undefined,
  entitlement_test_plan_name: undefined,

  // Stripe billing (optional, loaded separately)
  stripe_customer: undefined,
  stripe_subscriptions: undefined,
};

// =============================================================================
// SCENARIO FIXTURES
// =============================================================================

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
