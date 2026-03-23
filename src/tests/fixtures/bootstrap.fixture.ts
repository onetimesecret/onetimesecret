// src/tests/fixtures/bootstrap.fixture.ts
//
// Bootstrap payload fixtures for testing.
// These provide pre-configured states for common test scenarios.
//
// Fixtures derive from bootstrapSchema.parse({}) to ensure consistency
// with the canonical schema defaults, then override with test-specific values.

import { bootstrapSchema, type BootstrapPayload } from '@/schemas/contracts/bootstrap';
import type { CustomerCanonical } from '@/schemas/contracts/customer';

/**
 * Schema-derived defaults - the canonical baseline.
 * Use this when you need pure schema defaults without test customizations.
 */
export const schemaDefaults: BootstrapPayload = bootstrapSchema.parse({});

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
 * Derives from schemaDefaults (bootstrapSchema.parse({})) and overrides
 * with test-specific values like URLs, version info, and feature flags.
 *
 * This is the canonical test fixture — all scenario fixtures derive from it.
 */
export const baseBootstrap: BootstrapPayload = {
  ...schemaDefaults,

  // Test-specific URLs and hosts
  baseuri: 'https://test.onetimesecret.com',
  frontend_host: 'https://test.onetimesecret.com',
  site_host: 'test.onetimesecret.com',
  support_host: 'support.onetimesecret.com',

  // Test locales
  supported_locales: ['en', 'es', 'fr', 'de'],

  // Test version info
  ot_version: '0.20.0',
  ot_version_long: '0.20.0 (test)',
  ruby_version: 'ruby-335',

  // Enable billing for most tests
  billing_enabled: true,

  // Test CSRF token
  shrimp: 'test-csrf-token',

  // Test domain configuration
  canonical_domain: 'test.onetimesecret.com',
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

  // Test auth settings with explicit mode
  authentication: {
    ...schemaDefaults.authentication,
    mode: 'simple',
  },

  // Test region configuration
  regions: {
    identifier: 'US',
    enabled: false,
    current_jurisdiction: 'US',
    jurisdictions: [],
  },
  available_jurisdictions: ['US'],

  // Enable enjoyTheVue for tests
  enjoyTheVue: true,

  // Enable markdown in tests
  features: {
    ...schemaDefaults.features,
    markdown: true,
  },

  // Explicitly include optional fields for test key enumeration
  // These are undefined but need to be present for Object.keys() in tests
  customer_since: undefined,
  development: undefined,
  organization: undefined,
  entitlement_test_planid: undefined,
  entitlement_test_plan_name: undefined,
  nonce: null,
  homepage_mode: null,
  global_banner: null,
  domain_context: null,
  domain_locale: null,
  frontend_development: false,
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
