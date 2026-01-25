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
} from '../setup-bootstrap';
import type { BootstrapPayload } from '@/types/declarations/bootstrap';

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

    it('does not overwrite fields with undefined values', () => {
      store.update({ authenticated: true, email: 'test@example.com' });

      // Update with partial data (undefined fields)
      store.update({
        authenticated: false,
        email: undefined as unknown as string,
      });

      expect(store.authenticated).toBe(false);
      expect(store.email).toBe('test@example.com'); // Should NOT be overwritten
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

    it('resets regions configuration to defaults', () => {
      store.update({
        regions: {
          identifier: 'EU',
          enabled: true,
          current_jurisdiction: 'EU',
          jurisdictions: ['EU', 'US'],
        },
      });

      store.$reset();

      expect(store.regions.identifier).toBe('');
      expect(store.regions.enabled).toBe(false);
      expect(store.regions.jurisdictions).toEqual([]);
    });

    it('resets authentication settings to defaults', () => {
      store.update({
        authentication: {
          enabled: false,
          signup: false,
          signin: false,
          autoverify: true,
          required: true,
        },
      });

      store.$reset();

      expect(store.authentication.enabled).toBe(true);
      expect(store.authentication.signup).toBe(true);
      expect(store.authentication.signin).toBe(true);
      expect(store.authentication.autoverify).toBe(false);
      expect(store.authentication.required).toBe(false);
    });

    it('resets secret options to defaults', () => {
      store.update({
        secret_options: {
          default_ttl: 3600,
          ttl_options: [60, 120],
        },
      });

      store.$reset();

      expect(store.secret_options.default_ttl).toBe(604800);
      expect(store.secret_options.ttl_options).toEqual([
        300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000,
      ]);
    });

    it('resets UI configuration to defaults', () => {
      store.update({
        ui: {
          enabled: false,
          header: { enabled: false },
          footer_links: { enabled: true, groups: [] },
        },
      });

      store.$reset();

      expect(store.ui.enabled).toBe(true);
      expect(store.ui.header?.enabled).toBe(true);
      expect(store.ui.footer_links?.enabled).toBe(false);
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

    it('keeps _initialized flag true after reset', () => {
      // Per store comment: "We keep _initialized true because the store structure is still valid"
      mockGetBootstrapSnapshot.mockReturnValue(authenticatedBootstrap);
      store.init();
      expect(store.isInitialized).toBe(true);

      store.$reset();

      // Note: The actual DEFAULTS constant doesn't reset _initialized
      // This test documents the current behavior
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
});
