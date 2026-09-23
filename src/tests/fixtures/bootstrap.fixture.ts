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
  // Empty by default — mirrors production (set only when a Stripe custom
  // Checkout domain is configured) and avoids enabling the custom-domain
  // allowlist across unrelated tests. Scenario fixtures override as needed.
  checkout_host: '',

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

  // The serializer always emits a status (#4462); the base state is anonymous.
  // `.optional()` in the schema, so it is absent from schemaDefaults.
  auth_status: 'anonymous',

  // Test domain configuration
  canonical_domain: 'test.onetimesecret.com',
  // AC1 shape (#4063): LINK_DOMAINS unset, so the server resolves the pool to
  // [canonical_domain]. Scenario fixtures that exercise an operator pool
  // override this (and may exclude the canonical host entirely).
  link_domains: ['test.onetimesecret.com'],
  display_domain: 'test.onetimesecret.com',
  domain_branding: {
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
  //
  // `development` is NOT listed here (unlike below): the schema always
  // emits it via `.default(...)`, so BootstrapPayload['development'] is a
  // required `{ enabled; domain_context_enabled }` object, never undefined.
  // It's already present with its real default value via the schemaDefaults
  // spread above — this list is only for genuinely `.optional()`/`.nullish()`
  // fields (see the matching `DEFAULTS` comment in bootstrapStore.ts).
  customer_since: undefined,
  organization: undefined,
  // Snapshot ordering (ADR-046): absent unless the session is ordered.
  snapshot_epoch: undefined,
  snapshot_version: undefined,
  snapshot_generated_at: undefined,
  entitlement_preview_planid: undefined,
  entitlement_preview_plan_name: undefined,
  nonce: null,
  homepage_mode: null,
  global_banner: null,
  domain_context: null,
  domain_locale: null,
  frontend_development: false,
  // Brand fields (per-installation defaults from OT.conf['brand']).
  // null mirrors what the Ruby serializer emits when BRAND_* ENV is unset.
  brand_primary_color: null,
  brand_product_name: null,
  brand_product_domain: null,
  brand_support_email: null,
  brand_corner_style: null,
  brand_font_family: null,
  brand_button_text_light: null,
  brand_logo_url: null,
  brand_logo_dark_url: null,
  brand_logo_alt: null,
  brand_favicon_url: null,
};

// =============================================================================
// SCENARIO FIXTURES
// =============================================================================

/**
 * A valid ADR-046 ordering pair. The server sends one with EVERY payload that
 * reports a session (authenticated or MFA-pending), so the session fixtures
 * below carry it; anonymous and unavailable payloads never do. Use
 * `newerSnapshot()` to build the next snapshot of the same stream.
 */
export const snapshotOrdering = {
  snapshot_epoch: '0123456789abcdef0123456789abcdef',
  snapshot_version: '1758236400000001',
  snapshot_generated_at: '2026-09-17T17:28:59.123456Z',
} as const;

/** A second session's epoch: what a login elsewhere or an SID renewal produces. */
export const otherSnapshotEpoch = 'fedcba9876543210fedcba9876543210';

/**
 * Authenticated user bootstrap state.
 * User is fully authenticated with customer data.
 */
export const authenticatedBootstrap: BootstrapPayload = {
  ...baseBootstrap,
  ...snapshotOrdering,
  auth_status: 'authenticated',
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
  auth_status: 'anonymous',
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
  ...snapshotOrdering,
  auth_status: 'mfa_pending',
  authenticated: false,
  awaiting_mfa: true,
  had_valid_session: true,
  // No cust / custid / email: the server sends no identity until the second
  // factor is verified (AuthenticationSerializer, #4462).
};

/**
 * The session could not be verified (auth-DB outage, or an error-recovery
 * render that still had a session). NOT a sign-out, and no identity.
 * The refresh coordinator treats this as a failed refresh; hydration shows it
 * as `unavailable`.
 */
export const unavailableBootstrap: BootstrapPayload = {
  ...baseBootstrap,
  auth_status: 'unavailable',
  authenticated: false,
  awaiting_mfa: false,
  had_valid_session: true,
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
  entitlement_preview_planid: null,
  entitlement_preview_plan_name: null,
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

/**
 * The next snapshot of the same stream: same epoch, strictly greater version.
 * A refresh response must be newer than the snapshot the tab holds, or the
 * coordinator classifies it as an anomaly (ADR-046 rule 4).
 *
 * @param by - How far to advance; use increasing values for a sequence
 */
export function newerSnapshot(payload: BootstrapPayload, by: number = 1): BootstrapPayload {
  const current = BigInt(payload.snapshot_version ?? snapshotOrdering.snapshot_version);
  return {
    ...payload,
    snapshot_epoch: payload.snapshot_epoch ?? snapshotOrdering.snapshot_epoch,
    snapshot_version: (current + BigInt(by)).toString(),
  };
}

/** The same payload as the start of ANOTHER session's stream. */
export function inOtherEpoch(payload: BootstrapPayload): BootstrapPayload {
  return { ...payload, snapshot_epoch: otherSnapshotEpoch };
}

/**
 * Puts a bootstrap store into a given authentication state the only way
 * production can (#4458): by applying a complete, contract-valid snapshot.
 *
 * `bootstrapStore.update({ authenticated: true })` and
 * `authStore.$patch({ isAuthenticated: true })` no longer do anything: local
 * patches cannot state who is signed in, and authStore holds no flag.
 *
 * @example
 *   applyBootstrap(bootstrapStore, authenticatedBootstrap, { email: 'a@b.c' });
 *   applyBootstrap(bootstrapStore, anonymousBootstrap);
 */
export function applyBootstrap(
  store: { applySnapshot: (snapshot: BootstrapPayload) => void },
  scenario: BootstrapPayload,
  overrides: Partial<BootstrapPayload> = {}
): void {
  store.applySnapshot(bootstrapSchema.parse({ ...scenario, ...overrides }));
}
