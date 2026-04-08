// src/tests/stores/bootstrapStore.spec.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import * as bootstrapService from '@/services/bootstrap.service';
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { setupTestPinia } from '../setup';
import {
  authenticatedBootstrap,
  anonymousBootstrap,
  mfaPendingBootstrap,
  colonelBootstrap,
  customDomainsBootstrap,
  standaloneBootstrap,
  baseBootstrap,
  mockCustomer,
} from '@/tests/fixtures/bootstrap.fixture';
import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';

// Mock the bootstrap service
vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapSnapshot: vi.fn(),
  _resetForTesting: vi.fn(),
}));

describe('bootstrapStore', () => {
  let store: ReturnType<typeof useBootstrapStore>;
  let mockGetBootstrapSnapshot: Mock;

  beforeEach(async () => {
    // Reset the bootstrap service mock
    vi.clearAllMocks();
    mockGetBootstrapSnapshot = vi.mocked(bootstrapService.getBootstrapSnapshot);

    // Initialize test environment
    await setupTestPinia();
    store = useBootstrapStore();
  });

  afterEach(() => {
    store.$reset();
    vi.clearAllMocks();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Initialization', () => {
    it('initializes with default state before init() is called', () => {
      // Store should have default values before init
      expect(store.authenticated).toBe(false);
      expect(store.awaiting_mfa).toBe(false);
      expect(store.cust).toBeNull();
      expect(store.custid).toBe('');
      expect(store.email).toBe('');
      expect(store.locale).toBe('en');
      expect(store.isInitialized).toBe(false);
    });

    it('hydrates state from bootstrap snapshot on init()', () => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);

      const result = store.init();

      expect(result.isInitialized).toBe(true);
      expect(store.isInitialized).toBe(true);
      expect(store.authenticated).toBe(true);
      expect(store.cust).toEqual(mockCustomer);
      expect(store.custid).toBe(mockCustomer.extid);
      expect(store.email).toBe(mockCustomer.email);
    });

    it('only initializes once (idempotent)', () => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);

      // First init
      const result1 = store.init();
      expect(result1.isInitialized).toBe(true);
      expect(mockGetBootstrapSnapshot).toHaveBeenCalledTimes(1);

      // Second init should be a no-op
      const result2 = store.init();
      expect(result2.isInitialized).toBe(true);
      expect(mockGetBootstrapSnapshot).toHaveBeenCalledTimes(1); // Still only called once
    });

    it('uses defaults when no bootstrap snapshot available', () => {
      mockGetBootstrapSnapshot.mockReturnValue(null);

      const result = store.init();

      expect(result.isInitialized).toBe(true);
      expect(store.authenticated).toBe(false);
      expect(store.cust).toBeNull();
      expect(store.billing_enabled).toBe(false);
    });

    it('hydrates anonymous user state correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue(anonymousBootstrap);

      store.init();

      expect(store.authenticated).toBe(false);
      expect(store.awaiting_mfa).toBe(false);
      expect(store.had_valid_session).toBe(false);
      expect(store.cust).toBeNull();
      expect(store.custid).toBe('');
      expect(store.email).toBe('');
    });

    it('hydrates MFA pending state correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue(mfaPendingBootstrap);

      store.init();

      expect(store.authenticated).toBe(false);
      expect(store.awaiting_mfa).toBe(true);
      expect(store.had_valid_session).toBe(true);
      expect(store.cust).toEqual(mockCustomer);
    });

    it('hydrates colonel (admin) state correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue(colonelBootstrap);

      store.init();

      expect(store.authenticated).toBe(true);
      expect(store.cust?.role).toBe('colonel');
      expect(store.development?.enabled).toBe(true);
      expect(store.development?.domain_context_enabled).toBe(true);
    });

    it('hydrates custom domains state correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue(customDomainsBootstrap);

      store.init();

      expect(store.domains_enabled).toBe(true);
      expect(store.custom_domains).toEqual(['acme.example.com', 'widgets.example.com']);
    });

    it('hydrates standalone (billing disabled) state correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue(standaloneBootstrap);

      store.init();

      expect(store.billing_enabled).toBe(false);
      expect(store.authenticated).toBe(true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // UPDATE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('update()', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(anonymousBootstrap);
      store.init();
    });

    it('updates partial state correctly', () => {
      store.update({
        authenticated: true,
        email: 'updated@example.com',
      });

      expect(store.authenticated).toBe(true);
      expect(store.email).toBe('updated@example.com');
      // Other fields should remain unchanged
      expect(store.locale).toBe('en');
    });

    it('does not overwrite fields with undefined values (filterDefined)', () => {
      // Options API uses filterDefined which filters out undefined values
      store.update({ authenticated: true, email: 'test@example.com' });

      // Update with undefined - undefined is filtered out, so email is preserved
      store.update({
        authenticated: false,
        email: undefined as unknown as string,
      });

      expect(store.authenticated).toBe(false);
      // filterDefined removes undefined values, so email is NOT overwritten
      expect(store.email).toBe('test@example.com');
    });

    it('preserves fields not included in update payload', () => {
      // This is the correct way to preserve fields - don't include them
      store.update({ authenticated: true, email: 'test@example.com' });

      // Update without email field - email is preserved
      store.update({ authenticated: false });

      expect(store.authenticated).toBe(false);
      expect(store.email).toBe('test@example.com'); // Preserved
    });

    it('updates authentication state', () => {
      expect(store.authenticated).toBe(false);

      store.update({
        authenticated: true,
        awaiting_mfa: false,
        had_valid_session: true,
      });

      expect(store.authenticated).toBe(true);
      expect(store.awaiting_mfa).toBe(false);
      expect(store.had_valid_session).toBe(true);
    });

    it('updates user identity', () => {
      const newCustomer = { ...mockCustomer, email: 'new@example.com' };

      store.update({
        cust: newCustomer,
        custid: 'new-cust-id',
        email: 'new@example.com',
        customer_since: '2024-01-01',
        apitoken: 'new-api-token',
      });

      expect(store.cust).toEqual(newCustomer);
      expect(store.custid).toBe('new-cust-id');
      expect(store.email).toBe('new@example.com');
      expect(store.customer_since).toBe('2024-01-01');
      expect(store.apitoken).toBe('new-api-token');
    });

    it('updates locale settings', () => {
      store.update({
        locale: 'es',
        i18n_enabled: true,
        supported_locales: [
          { code: 'en', name: 'English', enabled: true },
          { code: 'es', name: 'Spanish', enabled: true },
        ],
        fallback_locale: 'en',
      });

      expect(store.locale).toBe('es');
      expect(store.i18n_enabled).toBe(true);
      expect(store.supported_locales).toHaveLength(2);
    });

    it('updates site configuration', () => {
      store.update({
        baseuri: 'https://new.example.com',
        frontend_host: 'https://new.example.com',
        site_host: 'new.example.com',
        ot_version: '1.0.0',
        shrimp: 'new-csrf-token',
      });

      expect(store.baseuri).toBe('https://new.example.com');
      expect(store.frontend_host).toBe('https://new.example.com');
      expect(store.site_host).toBe('new.example.com');
      expect(store.ot_version).toBe('1.0.0');
      expect(store.shrimp).toBe('new-csrf-token');
    });

    it('updates feature flags', () => {
      store.update({
        billing_enabled: true,
        regions_enabled: true,
        domains_enabled: true,
        d9s_enabled: true,
      });

      expect(store.billing_enabled).toBe(true);
      expect(store.regions_enabled).toBe(true);
      expect(store.domains_enabled).toBe(true);
      expect(store.d9s_enabled).toBe(true);
    });

    it('updates domain configuration', () => {
      store.update({
        canonical_domain: 'custom.example.com',
        domain_strategy: 'custom',
        domain_id: 'domain-123',
        display_domain: 'custom.example.com',
        custom_domains: ['sub1.example.com', 'sub2.example.com'],
      });

      expect(store.canonical_domain).toBe('custom.example.com');
      expect(store.domain_strategy).toBe('custom');
      expect(store.domain_id).toBe('domain-123');
      expect(store.custom_domains).toEqual(['sub1.example.com', 'sub2.example.com']);
    });

    it('updates UI configuration', () => {
      const newUi = {
        enabled: true,
        header: {
          enabled: true,
          branding: {
            logo: { url: '/logo.png', alt: 'Logo', link_to: '/' },
            site_name: 'Custom Site',
          },
        },
        footer_links: {
          enabled: true,
          groups: [
            {
              name: 'Legal',
              links: [{ text: 'Privacy', url: '/privacy' }],
            },
          ],
        },
      };

      store.update({ ui: newUi });

      expect(store.ui.enabled).toBe(true);
      expect(store.ui.header?.enabled).toBe(true);
      expect(store.ui.footer_links?.enabled).toBe(true);
    });

    it('updates stripe/billing data', () => {
      const stripeCustomer = { id: 'cus_123' } as any;
      const stripeSubscriptions = [{ id: 'sub_123' }] as any;

      store.update({
        stripe_customer: stripeCustomer,
        stripe_subscriptions: stripeSubscriptions,
      });

      expect(store.stripe_customer).toEqual(stripeCustomer);
      expect(store.stripe_subscriptions).toEqual(stripeSubscriptions);
    });

    it('updates organization data', () => {
      store.update({
        organization: { planid: 'pro-plan' },
      });

      expect(store.organization?.planid).toBe('pro-plan');
    });

    it('updates entitlement test mode (colonel)', () => {
      store.update({
        entitlement_test_planid: 'test-plan-id',
        entitlement_test_plan_name: 'Test Plan',
      });

      expect(store.entitlement_test_planid).toBe('test-plan-id');
      expect(store.entitlement_test_plan_name).toBe('Test Plan');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REFRESH TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('refresh()', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(anonymousBootstrap);
      store.init();
    });

    it('fetches /bootstrap/me endpoint and updates state', async () => {
      const refreshedState: Partial<BootstrapPayload> = {
        authenticated: true,
        email: 'refreshed@example.com',
        cust: mockCustomer,
      };

      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve(refreshedState),
      });

      await store.refresh();

      expect(global.fetch).toHaveBeenCalledWith('/bootstrap/me', {
        method: 'GET',
        credentials: 'same-origin',
        headers: { Accept: 'application/json' },
      });
      expect(store.authenticated).toBe(true);
      expect(store.email).toBe('refreshed@example.com');
    });

    it('throws error on failed fetch', async () => {
      global.fetch = vi.fn().mockResolvedValue({
        ok: false,
        status: 500,
      });

      await expect(store.refresh()).rejects.toThrow(
        '[BootstrapStore] Failed to refresh state: 500'
      );
    });

    it('throws error on network failure', async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error('Network error'));

      await expect(store.refresh()).rejects.toThrow('Network error');
    });

    it('updates CSRF token on refresh', async () => {
      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ shrimp: 'new-csrf-token' }),
      });

      await store.refresh();

      expect(store.shrimp).toBe('new-csrf-token');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('$reset()', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();
    });

    it('resets authentication state to defaults', () => {
      expect(store.authenticated).toBe(true);

      store.$reset();

      expect(store.authenticated).toBe(false);
      expect(store.awaiting_mfa).toBe(false);
      expect(store.had_valid_session).toBe(false);
    });

    it('resets user identity to defaults', () => {
      expect(store.cust).not.toBeNull();
      expect(store.email).toBe(mockCustomer.email);

      store.$reset();

      expect(store.cust).toBeNull();
      expect(store.custid).toBe('');
      expect(store.email).toBe('');
      expect(store.customer_since).toBeUndefined();
      expect(store.apitoken).toBeUndefined();
    });

    it('resets locale settings to defaults', () => {
      store.update({ locale: 'es', i18n_enabled: false });

      store.$reset();

      expect(store.locale).toBe('en');
      expect(store.i18n_enabled).toBe(true);
      expect(store.fallback_locale).toBe('en');
    });

    it('resets site configuration to defaults', () => {
      store.update({
        baseuri: 'https://custom.example.com',
        ot_version: '2.0.0',
      });

      store.$reset();

      expect(store.baseuri).toBe('');
      expect(store.frontend_host).toBe('');
      expect(store.site_host).toBe('');
      expect(store.ot_version).toBe('');
      expect(store.shrimp).toBe('');
    });

    it('resets feature flags to defaults', () => {
      store.update({
        billing_enabled: true,
        regions_enabled: true,
        domains_enabled: true,
      });

      store.$reset();

      expect(store.billing_enabled).toBe(false);
      expect(store.regions_enabled).toBe(false);
      expect(store.domains_enabled).toBe(false);
      expect(store.d9s_enabled).toBe(false);
    });

    it('resets domain configuration to defaults', () => {
      store.update({
        canonical_domain: 'custom.example.com',
        domain_strategy: 'custom',
        custom_domains: ['sub.example.com'],
      });

      store.$reset();

      expect(store.canonical_domain).toBe('');
      expect(store.domain_strategy).toBe('canonical');
      expect(store.domain_id).toBe('');
      expect(store.custom_domains).toEqual([]);
    });

    it('resets all server config fields to defaults (unlike resetForLogout)', () => {
      store.update({
        authentication: { enabled: false, signup: false },
        ui: { enabled: false },
        features: { markdown: true },
        regions: {
          identifier: 'EU',
          enabled: true,
          current_jurisdiction: 'EU',
          jurisdictions: [{ identifier: 'EU', display_name: 'Europe', domain: 'eu.example.com', icon: { collection: 'flags', name: 'eu' }, enabled: true }],
        },
      });

      store.$reset();

      // $reset() resets EVERYTHING to DEFAULTS, including server config
      expect(store.authentication?.enabled).toBe(true); // Default is true
      expect(store.ui.enabled).toBe(true); // Default is true
    });

    it('resets billing data to defaults', () => {
      store.update({
        stripe_customer: { id: 'cus_123' } as any,
        stripe_subscriptions: [{ id: 'sub_123' }] as any,
      });

      store.$reset();

      expect(store.stripe_customer).toBeUndefined();
      expect(store.stripe_subscriptions).toBeUndefined();
    });

    it('resets entitlement test mode to defaults', () => {
      store.update({
        entitlement_test_planid: 'test-plan',
        entitlement_test_plan_name: 'Test Plan',
      });

      store.$reset();

      expect(store.entitlement_test_planid).toBeUndefined();
      expect(store.entitlement_test_plan_name).toBeUndefined();
    });

    it('resets organization data to defaults', () => {
      store.update({ organization: { planid: 'pro' } });

      store.$reset();

      expect(store.organization).toBeUndefined();
    });

    it('resets _initialized flag to false', () => {
      // Options API $reset() returns to initial state() which has _initialized: false
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();
      expect(store.isInitialized).toBe(true);

      store.$reset();

      // $reset() restores initial state including _initialized: false
      expect(store.isInitialized).toBe(false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // resetForLogout() TESTS - Preserves Server Config
  // ═══════════════════════════════════════════════════════════════════════════

  describe('resetForLogout()', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();
    });

    it('resets user authentication state to defaults', () => {
      expect(store.authenticated).toBe(true);

      store.resetForLogout();

      expect(store.authenticated).toBe(false);
      expect(store.awaiting_mfa).toBe(false);
      expect(store.had_valid_session).toBe(false);
    });

    it('resets user identity to defaults', () => {
      expect(store.cust).not.toBeNull();

      store.resetForLogout();

      expect(store.cust).toBeNull();
      expect(store.custid).toBe('');
      expect(store.email).toBe('');
    });

    it('preserves regions configuration through reset (server config)', () => {
      const jurisdictions = [
        { identifier: 'EU', display_name: 'Europe', domain: 'eu.example.com', icon: { collection: 'flags', name: 'eu' }, enabled: true },
        { identifier: 'US', display_name: 'United States', domain: 'us.example.com', icon: { collection: 'flags', name: 'us' }, enabled: true },
      ];
      store.update({
        regions: {
          identifier: 'EU',
          enabled: true,
          current_jurisdiction: 'EU',
          jurisdictions,
        },
      });

      store.resetForLogout();

      // Server config fields are NOT reset
      expect(store.regions?.identifier).toBe('EU');
      expect(store.regions?.enabled).toBe(true);
      expect(store.regions?.jurisdictions).toEqual(jurisdictions);
    });

    it('preserves authentication settings through reset (server config)', () => {
      store.update({
        authentication: {
          enabled: false,
          signup: false,
          signin: false,
          autoverify: true,
          required: true,
        },
      });

      store.resetForLogout();

      // Server config: retains the values set via update()
      expect(store.authentication?.enabled).toBe(false);
      expect(store.authentication?.signup).toBe(false);
      expect(store.authentication?.signin).toBe(false);
      expect(store.authentication?.autoverify).toBe(true);
      expect(store.authentication?.required).toBe(true);
    });

    it('preserves secret options through reset (server config)', () => {
      store.update({
        secret_options: {
          default_ttl: 3600,
          ttl_options: [60, 120],
        },
      });

      store.resetForLogout();

      // Server config: retains the values set via update()
      expect(store.secret_options.default_ttl).toBe(3600);
      expect(store.secret_options.ttl_options).toEqual([60, 120]);
    });

    it('preserves UI configuration through reset (server config)', () => {
      store.update({
        ui: {
          enabled: false,
          header: { enabled: false },
          footer_links: { enabled: true, groups: [] },
        },
      });

      store.resetForLogout();

      // Server config: retains the values set via update()
      expect(store.ui.enabled).toBe(false);
      expect(store.ui.header?.enabled).toBe(false);
      expect(store.ui.footer_links?.enabled).toBe(true);
    });

    it('preserves features configuration through reset (server config)', () => {
      store.update({
        features: { markdown: false },
      });

      store.resetForLogout();

      expect(store.features.markdown).toBe(false);
    });

    it('preserves diagnostics configuration through reset (server config)', () => {
      const diagnosticsConfig = {
        sentry: {
          dsn: 'https://test@sentry.io/123',
          enabled: true,
          debug: false,
          logErrors: true,
          trackComponents: true,
        },
      };

      store.update({ diagnostics: diagnosticsConfig });

      store.resetForLogout();

      expect(store.diagnostics).toEqual(diagnosticsConfig);
    });

    it('keeps _initialized flag true after resetForLogout', () => {
      expect(store.isInitialized).toBe(true);

      store.resetForLogout();

      // resetForLogout() preserves _initialized because the store structure is still valid
      expect(store.isInitialized).toBe(true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPUTED GETTERS TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Computed Getters', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(baseBootstrap);
      store.init();
    });

    describe('isInitialized', () => {
      it('returns false before init()', async () => {
        // Create fresh store without init
        await setupTestPinia();
        const freshStore = useBootstrapStore();

        expect(freshStore.isInitialized).toBe(false);
      });

      it('returns true after init()', () => {
        expect(store.isInitialized).toBe(true);
      });
    });

    describe('headerConfig', () => {
      it('returns header configuration from UI', () => {
        store.update({
          ui: {
            enabled: true,
            header: {
              enabled: true,
              branding: {
                logo: { url: '/logo.png', alt: 'Logo', link_to: '/' },
                site_name: 'My Site',
              },
            },
          },
        });

        expect(store.headerConfig?.enabled).toBe(true);
        expect(store.headerConfig?.branding?.site_name).toBe('My Site');
      });

      it('returns undefined when header not configured', () => {
        store.update({
          ui: {
            enabled: true,
          },
        });

        expect(store.headerConfig).toBeUndefined();
      });
    });

    describe('footerLinksConfig', () => {
      it('returns footer links configuration from UI', () => {
        store.update({
          ui: {
            enabled: true,
            footer_links: {
              enabled: true,
              groups: [
                {
                  name: 'Company',
                  links: [
                    { text: 'About', url: '/about' },
                    { text: 'Contact', url: '/contact' },
                  ],
                },
              ],
            },
          },
        });

        expect(store.footerLinksConfig?.enabled).toBe(true);
        expect(store.footerLinksConfig?.groups).toHaveLength(1);
        expect(store.footerLinksConfig?.groups[0].name).toBe('Company');
      });

      it('returns undefined when footer links not configured', () => {
        store.update({
          ui: {
            enabled: true,
          },
        });

        expect(store.footerLinksConfig).toBeUndefined();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REACTIVITY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Reactivity', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(anonymousBootstrap);
      store.init();
    });

    it('update() triggers reactive changes', () => {
      const initialAuth = store.authenticated;
      expect(initialAuth).toBe(false);

      store.update({ authenticated: true });

      expect(store.authenticated).toBe(true);
    });

    it('computed getter updates when underlying ref changes', () => {
      // Initial state
      expect(store.headerConfig).toBeUndefined();

      // Update UI
      store.update({
        ui: {
          enabled: true,
          header: { enabled: true },
        },
      });

      // Computed should reflect the change
      expect(store.headerConfig?.enabled).toBe(true);
    });

    it('individual refs can be updated independently', () => {
      // Direct property updates (via Pinia's auto-unwrapping)
      const originalEmail = store.email;

      store.update({ locale: 'fr' });

      expect(store.locale).toBe('fr');
      expect(store.email).toBe(originalEmail); // Unchanged
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EDGE CASE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Edge Cases', () => {
    it('handles empty bootstrap snapshot gracefully', () => {
      mockGetBootstrapSnapshot.mockReturnValue({});

      store.init();

      // Should use defaults for all missing fields
      expect(store.authenticated).toBe(false);
      expect(store.locale).toBe('en');
      expect(store.isInitialized).toBe(true);
    });

    it('handles partial bootstrap snapshot', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        authenticated: true,
        email: 'partial@example.com',
        // All other fields missing
      });

      store.init();

      expect(store.authenticated).toBe(true);
      expect(store.email).toBe('partial@example.com');
      // Missing fields should use defaults
      expect(store.locale).toBe('en');
      expect(store.billing_enabled).toBe(false);
    });

    it('handles null customer correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        ...authenticatedBootstrap,
        cust: null,
      });

      store.init();

      expect(store.cust).toBeNull();
    });

    it('handles empty arrays correctly', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        supported_locales: [],
        custom_domains: [],
        available_jurisdictions: [],
        messages: [],
      });

      store.init();

      expect(store.supported_locales).toEqual([]);
      expect(store.custom_domains).toEqual([]);
      expect(store.available_jurisdictions).toEqual([]);
      expect(store.messages).toEqual([]);
    });

    it('preserves complex nested objects on update', () => {
      mockGetBootstrapSnapshot.mockReturnValue(baseBootstrap);
      store.init();

      const complexUi = {
        enabled: true,
        header: {
          enabled: true,
          branding: {
            logo: { url: '/custom.png', alt: 'Custom', link_to: '/home' },
            site_name: 'Complex Site',
          },
          navigation: { enabled: true },
        },
        footer_links: {
          enabled: true,
          groups: [
            {
              name: 'Group 1',
              i18n_key: 'footer.group1',
              links: [
                { text: 'Link 1', url: '/link1', external: true },
                { i18n_key: 'footer.link2', url: '/link2' },
              ],
            },
          ],
        },
      };

      store.update({ ui: complexUi });

      expect(store.ui).toEqual(complexUi);
      expect(store.ui.header?.branding?.site_name).toBe('Complex Site');
      expect(store.ui.footer_links?.groups[0].links).toHaveLength(2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INTEGRATION WITH OTHER STORES
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Store Integration Patterns', () => {
    it('provides data for authStore initialization', () => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();

      // authStore would read these values
      expect(store.authenticated).toBe(true);
      expect(store.awaiting_mfa).toBe(false);
      expect(store.had_valid_session).toBe(true);
      expect(store.cust).not.toBeNull();
    });

    it('provides CSRF token for csrfStore', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        ...baseBootstrap,
        shrimp: 'test-csrf-token-123',
      });
      store.init();

      expect(store.shrimp).toBe('test-csrf-token-123');
    });

    it('provides locale data for languageStore', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        ...baseBootstrap,
        locale: 'es',
        supported_locales: [
          { code: 'en', name: 'English', enabled: true },
          { code: 'es', name: 'Spanish', enabled: true },
        ],
        i18n_enabled: true,
      });
      store.init();

      expect(store.locale).toBe('es');
      expect(store.supported_locales).toHaveLength(2);
      expect(store.i18n_enabled).toBe(true);
    });

    it('provides organization data for organizationStore', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        ...authenticatedBootstrap,
        organization: { planid: 'enterprise' },
      });
      store.init();

      expect(store.organization?.planid).toBe('enterprise');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCHEMA CONSISTENCY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Schema Consistency', () => {
    /**
     * The bootstrap schema (bootstrap.schema.ts) defines BOOTSTRAP_UI_DEFAULTS
     * for UI-specific fields. The store DEFAULTS must remain consistent with
     * these schema defaults for overlapping fields.
     *
     * This test ensures the two sources don't drift apart.
     */
    it('store DEFAULTS match schema BOOTSTRAP_UI_DEFAULTS for overlapping fields', async () => {
      const { BOOTSTRAP_UI_DEFAULTS } = await import('@/tests/contracts/bootstrap-test-schema');

      // Create fresh store to verify initial DEFAULTS
      await setupTestPinia();
      const freshStore = useBootstrapStore();

      // UI configuration
      expect(freshStore.ui.enabled).toBe(BOOTSTRAP_UI_DEFAULTS.ui.enabled);

      // Messages (both should default to empty array)
      expect(freshStore.messages).toEqual(BOOTSTRAP_UI_DEFAULTS.messages);

      // Features
      expect(freshStore.features.markdown).toBe(BOOTSTRAP_UI_DEFAULTS.features.markdown);

      // Locale defaults
      expect(freshStore.default_locale).toBe(BOOTSTRAP_UI_DEFAULTS.default_locale);
      expect(freshStore.supported_locales).toEqual(BOOTSTRAP_UI_DEFAULTS.supported_locales);

      // Development (both undefined by default)
      expect(freshStore.development).toBe(BOOTSTRAP_UI_DEFAULTS.development);

      // Organization (both undefined by default)
      expect(freshStore.organization).toBe(BOOTSTRAP_UI_DEFAULTS.organization);
    });

    it('schema defaults represent valid BootstrapPayload subset', async () => {
      const { BOOTSTRAP_UI_DEFAULTS, bootstrapUiSchema } = await import(
        '@/tests/contracts/bootstrap-test-schema'
      );

      // Parsing an empty object should produce the same defaults
      const parsedDefaults = bootstrapUiSchema.parse({});

      expect(parsedDefaults).toEqual(BOOTSTRAP_UI_DEFAULTS);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // OPTIONS API COMPATIBILITY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Options API Compatibility', () => {
    /**
     * These tests verify behaviors that must work identically whether
     * the store uses Setup API or Options API internally.
     * Tests focus on public interface, not implementation details.
     */

    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(anonymousBootstrap);
      store.init();
    });

    it('update() merges partial state without replacing entire state', () => {
      // Set up initial state with multiple fields
      store.update({
        authenticated: true,
        email: 'first@example.com',
        locale: 'es',
      });

      // Partial update should only change specified fields
      store.update({ locale: 'fr' });

      expect(store.locale).toBe('fr');
      expect(store.authenticated).toBe(true); // Preserved
      expect(store.email).toBe('first@example.com'); // Preserved
    });

    it('sequential updates accumulate correctly', () => {
      store.update({ authenticated: true });
      store.update({ email: 'step1@example.com' });
      store.update({ custid: 'cust-123' });
      store.update({ locale: 'de' });

      expect(store.authenticated).toBe(true);
      expect(store.email).toBe('step1@example.com');
      expect(store.custid).toBe('cust-123');
      expect(store.locale).toBe('de');
    });

    it('$reset() can be called multiple times safely', () => {
      store.update({ authenticated: true, email: 'test@example.com' });

      store.$reset();
      expect(store.authenticated).toBe(false);

      // Update again
      store.update({ authenticated: true });
      expect(store.authenticated).toBe(true);

      // Reset again
      store.$reset();
      expect(store.authenticated).toBe(false);
    });

    it('store can be re-initialized after $reset()', async () => {
      // Initial setup (beforeEach already called init() with anonymousBootstrap)
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);

      // Reset clears everything including _initialized
      store.$reset();
      expect(store.authenticated).toBe(false);
      expect(store.isInitialized).toBe(false); // $reset() also resets _initialized

      // Re-initialization works because _initialized is now false
      const result = store.init();
      expect(result.isInitialized).toBe(true);
      expect(store.authenticated).toBe(true); // Now uses authenticatedBootstrap
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVER CONFIG PRESERVATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Server Config Preservation', () => {
    /**
     * Server configuration fields must NOT be reset on logout (resetForLogout).
     * These are set by the server at startup and persist until full page reload.
     *
     * Note: The built-in $reset() does a full reset to DEFAULTS.
     * Use resetForLogout() for logout scenarios that preserve server config.
     */

    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();
    });

    it('preserves features configuration through resetForLogout', () => {
      store.update({
        features: {
          markdown: false,
        },
      });

      store.resetForLogout();

      // Server config fields persist
      expect(store.features.markdown).toBe(false);
    });

    it('preserves diagnostics configuration through resetForLogout', () => {
      const diagnosticsConfig = {
        enabled: true,
        domains: true,
        regions: true,
        entitlements: true,
        locales: true,
      };

      store.update({ diagnostics: diagnosticsConfig });

      store.resetForLogout();

      // Server config fields persist
      expect(store.diagnostics).toEqual(diagnosticsConfig);
    });

    it('preserves all server config fields together through resetForLogout', () => {
      // Set up all server config fields
      const sentryConfig = { dsn: 'https://test@sentry.io/123', enabled: true, logErrors: true, trackComponents: true };
      store.update({
        authentication: { enabled: false, signup: false, signin: true },
        ui: { enabled: false, header: { enabled: false } },
        features: { markdown: false },
        regions: {
          identifier: 'EU',
          enabled: true,
          current_jurisdiction: 'EU',
          jurisdictions: [{ identifier: 'EU', display_name: 'Europe', domain: 'eu.example.com', icon: { collection: 'flags', name: 'eu' }, enabled: true }],
        },
        secret_options: { default_ttl: 7200, ttl_options: [300, 600] },
        diagnostics: { sentry: sentryConfig },
      });

      store.resetForLogout();

      // All server config fields should persist
      expect(store.authentication?.enabled).toBe(false);
      expect(store.ui.enabled).toBe(false);
      expect(store.features.markdown).toBe(false);
      expect(store.regions?.identifier).toBe('EU');
      expect(store.secret_options.default_ttl).toBe(7200);
      expect(store.diagnostics?.sentry?.enabled).toBe(true);
    });

    it('clears user-specific fields while preserving server config', () => {
      // Set both user and server config
      store.update({
        // User-specific
        authenticated: true,
        email: 'user@example.com',
        cust: mockCustomer,
        stripe_customer: { id: 'cus_123' } as any,
        // Server config
        authentication: { enabled: false },
        features: { markdown: false },
      });

      store.resetForLogout();

      // User fields are cleared
      expect(store.authenticated).toBe(false);
      expect(store.email).toBe('');
      expect(store.cust).toBeNull();
      expect(store.stripe_customer).toBeUndefined();

      // Server config persists
      expect(store.authentication?.enabled).toBe(false);
      expect(store.features.markdown).toBe(false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ADDITIONAL FIELD COVERAGE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Additional Field Coverage', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(baseBootstrap);
      store.init();
    });

    it('updates has_password field', () => {
      expect(store.has_password).toBe(false);

      store.update({ has_password: true });

      expect(store.has_password).toBe(true);
    });

    it('updates support_host field', () => {
      store.update({ support_host: 'help.example.com' });

      expect(store.support_host).toBe('help.example.com');
    });

    it('updates version fields', () => {
      store.update({
        ot_version: '1.2.3',
        ot_version_long: '1.2.3-beta.1 (abc123)',
        ruby_version: 'ruby-340',
      });

      expect(store.ot_version).toBe('1.2.3');
      expect(store.ot_version_long).toBe('1.2.3-beta.1 (abc123)');
      expect(store.ruby_version).toBe('ruby-340');
    });

    it('updates enjoyTheVue flag', () => {
      store.update({ enjoyTheVue: false });

      expect(store.enjoyTheVue).toBe(false);
    });

    it('updates homepage_mode and global_banner', () => {
      store.update({
        homepage_mode: 'marketing',
        global_banner: 'System maintenance scheduled',
      });

      expect(store.homepage_mode).toBe('marketing');
      expect(store.global_banner).toBe('System maintenance scheduled');
    });

    it('updates domain_branding and domain_logo', () => {
      const branding = {
        allow_public_homepage: true,
        button_text_light: false,
        corner_style: 'square' as const,
        font_family: 'serif' as const,
        primary_color: '#ff0000',
      };

      store.update({
        domain_branding: branding,
        domain_logo: '/custom-logo.svg',
      });

      expect(store.domain_branding).toEqual(branding);
      expect(store.domain_logo).toBe('/custom-logo.svg');
    });

    it('updates domain_context field', () => {
      store.update({ domain_context: 'custom-domain-context' });

      expect(store.domain_context).toBe('custom-domain-context');
    });

    it('updates messages array', () => {
      const messages = [
        { type: 'info' as const, content: 'Welcome message' },
        { type: 'warning' as const, content: 'Maintenance soon' },
      ];

      store.update({ messages });

      expect(store.messages).toEqual(messages);
      expect(store.messages).toHaveLength(2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REFRESH EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════════

  describe('refresh() Edge Cases', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();
    });

    it('refresh() updates all fields from server response', async () => {
      const serverResponse: Partial<BootstrapPayload> = {
        authenticated: false,
        awaiting_mfa: true,
        email: 'changed@example.com',
        locale: 'fr',
        shrimp: 'new-token',
      };

      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve(serverResponse),
      });

      await store.refresh();

      expect(store.authenticated).toBe(false);
      expect(store.awaiting_mfa).toBe(true);
      expect(store.email).toBe('changed@example.com');
      expect(store.locale).toBe('fr');
      expect(store.shrimp).toBe('new-token');
    });

    it('refresh() preserves fields not in server response', async () => {
      // Set initial state
      store.update({ locale: 'es', billing_enabled: true });

      // Server response only updates some fields
      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ authenticated: false }),
      });

      await store.refresh();

      // Updated field
      expect(store.authenticated).toBe(false);
      // Preserved fields (not in response)
      expect(store.locale).toBe('es');
      expect(store.billing_enabled).toBe(true);
    });

    it('refresh() handles empty response gracefully', async () => {
      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({}),
      });

      // Should not throw
      await expect(store.refresh()).resolves.toBeUndefined();

      // State should be unchanged
      expect(store.authenticated).toBe(true);
    });

    it('refresh() handles various HTTP error codes', async () => {
      const errorCodes = [400, 401, 403, 404, 500, 502, 503];

      for (const status of errorCodes) {
        global.fetch = vi.fn().mockResolvedValue({
          ok: false,
          status,
        });

        await expect(store.refresh()).rejects.toThrow(
          `[BootstrapStore] Failed to refresh state: ${status}`
        );
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DEEP NESTED OBJECT TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Deep Nested Object Handling', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(baseBootstrap);
      store.init();
    });

    it('updates deeply nested UI header navigation', () => {
      const uiWithNavigation = {
        enabled: true,
        header: {
          enabled: true,
          branding: {
            logo: { url: '/logo.png', alt: 'Logo', link_to: '/' },
            site_name: 'Test Site',
          },
          navigation: {
            enabled: true,
            links: [
              { text: 'Home', url: '/' },
              { text: 'About', url: '/about', external: false },
            ],
          },
        },
      };

      store.update({ ui: uiWithNavigation });

      expect(store.ui.header?.navigation?.enabled).toBe(true);
      expect(store.ui.header?.navigation?.links).toHaveLength(2);
    });

    it('updates deeply nested regions configuration', () => {
      const jurisdictions = [
        { identifier: 'EU', display_name: 'Europe', domain: 'eu.example.com', icon: { collection: 'flags', name: 'eu' }, enabled: true },
        { identifier: 'US', display_name: 'United States', domain: 'us.example.com', icon: { collection: 'flags', name: 'us' }, enabled: true },
        { identifier: 'CA', display_name: 'Canada', domain: 'ca.example.com', icon: { collection: 'flags', name: 'ca' }, enabled: true },
      ];
      const regionsConfig = {
        identifier: 'EU',
        enabled: true,
        current_jurisdiction: 'EU',
        jurisdictions,
      };

      store.update({ regions: regionsConfig });

      expect(store.regions?.identifier).toBe('EU');
      expect(store.regions?.jurisdictions).toHaveLength(3);
      expect(store.regions?.jurisdictions?.find(j => j.identifier === 'CA')).toBeDefined();
    });

    it('replaces entire nested object on update (not deep merge)', () => {
      // First update with full UI
      store.update({
        ui: {
          enabled: true,
          header: { enabled: true },
          footer_links: { enabled: true, groups: [] },
        },
      });

      // Second update with partial UI replaces the whole object
      store.update({
        ui: {
          enabled: false,
        },
      });

      // The entire UI object is replaced, not merged
      expect(store.ui.enabled).toBe(false);
      expect(store.ui.header).toBeUndefined();
      expect(store.ui.footer_links).toBeUndefined();
    });

    it('handles customer object with all fields', () => {
      const fullCustomer = {
        ...mockCustomer,
        feature_flags: { beta: true, experimental: true },
        secrets_created: 100,
        last_login: new Date(),
      };

      store.update({ cust: fullCustomer });

      expect(store.cust?.feature_flags?.beta).toBe(true);
      expect(store.cust?.secrets_created).toBe(100);
      expect(store.cust?.last_login).toBeInstanceOf(Date);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPE COERCION EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Type Edge Cases', () => {
    beforeEach(() => {
      mockGetBootstrapSnapshot.mockReturnValue(baseBootstrap);
      store.init();
    });

    it('handles boolean false values correctly (not treated as undefined)', () => {
      store.update({ authenticated: true });
      expect(store.authenticated).toBe(true);

      store.update({ authenticated: false });
      expect(store.authenticated).toBe(false);
    });

    it('handles empty string values correctly', () => {
      store.update({ email: 'test@example.com' });
      expect(store.email).toBe('test@example.com');

      store.update({ email: '' });
      expect(store.email).toBe('');
    });

    it('handles zero values correctly', () => {
      store.update({
        secret_options: { default_ttl: 3600, ttl_options: [60, 120] },
      });

      store.update({
        secret_options: { default_ttl: 0, ttl_options: [] },
      });

      expect(store.secret_options.default_ttl).toBe(0);
      expect(store.secret_options.ttl_options).toEqual([]);
    });

    it('handles null values for nullable fields', () => {
      store.update({ cust: mockCustomer });
      expect(store.cust).not.toBeNull();

      store.update({ cust: null });
      expect(store.cust).toBeNull();
    });

    it('handles undefined optional fields', () => {
      store.update({ customer_since: '2024-01-01' });
      expect(store.customer_since).toBe('2024-01-01');

      store.update({ customer_since: undefined });
      // undefined should not overwrite the existing value
      expect(store.customer_since).toBe('2024-01-01');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Initialization Edge Cases', () => {
    it('handles initialization with undefined values in snapshot', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        authenticated: true,
        email: undefined,
        cust: undefined,
      });

      store.init();

      expect(store.authenticated).toBe(true);
      // Undefined values should not overwrite defaults
      expect(store.email).toBe('');
      expect(store.cust).toBeNull();
    });

    it('handles initialization with null values for optional fields', () => {
      mockGetBootstrapSnapshot.mockReturnValue({
        ...baseBootstrap,
        customer_since: null,
        apitoken: null,
      });

      store.init();

      // These should be set to the provided null values
      // (or schema-defined behavior)
      expect(store.isInitialized).toBe(true);
    });

    it('getBootstrapSnapshot is only called once per init', () => {
      mockGetBootstrapSnapshot.mockReturnValue(baseBootstrap);

      store.init();
      store.init();
      store.init();

      expect(mockGetBootstrapSnapshot).toHaveBeenCalledTimes(1);
    });

    it('falls back to defaults when getBootstrapSnapshot throws', () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      const parseError = new Error('Parse error');
      mockGetBootstrapSnapshot.mockImplementation(() => {
        throw parseError;
      });

      const result = store.init();

      // Should still be initialized
      expect(result.isInitialized).toBe(true);
      expect(store.isInitialized).toBe(true);

      // Should have default values
      expect(store.authenticated).toBe(false);
      expect(store.cust).toBeNull();
      expect(store.email).toBe('');

      // Should log the error
      expect(consoleSpy).toHaveBeenCalledWith(
        '[BootstrapStore.init] Failed to initialize from snapshot, using defaults:',
        parseError
      );

      consoleSpy.mockRestore();
    });
  });
});
