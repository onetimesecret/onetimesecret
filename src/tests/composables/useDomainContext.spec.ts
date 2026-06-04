// src/tests/composables/useDomainContext.spec.ts

import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { nextTick } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { BulkPermissionsResponse } from '@/schemas/api/account/responses/permissions';

// --- Mock state ---

const emptyResponse: BulkPermissionsResponse = { organizations: [] };
const mockFetchAllPermissions = vi.fn().mockResolvedValue(emptyResponse);

const mockOrganizationStoreState = {
  currentOrganization: null as { objid: string; extid: string } | null,
};

// Mock useResourcePermissions - the composable now uses this instead of domainsStore
vi.mock('@/shared/composables/useResourcePermissions', () => ({
  useResourcePermissions: () => ({
    fetchAllPermissions: mockFetchAllPermissions,
  }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrganizationStoreState,
}));

/**
 * Build a BulkPermissionsResponse with domains for a given org extid.
 */
function buildPermissionsResponse(
  orgExtid: string,
  domains: string[],
  opts?: { role?: string; entitlements?: string[] }
): BulkPermissionsResponse {
  return {
    organizations: [
      {
        extid: orgExtid,
        display_name: `Org ${orgExtid}`,
        is_default: true,
        membership: {
          role: (opts?.role ?? 'owner') as 'owner' | 'admin' | 'member',
          status: 'active',
          provisioning_source: null,
          invited_at: null,
          joined_at: '2026-01-01',
          entitlements: opts?.entitlements ?? ['custom_domains'],
        },
        permissions: {
          can_view: true,
          can_edit: true,
          can_delete: false,
          can_manage_settings: true,
        },
        domains: domains.map((d) => ({
          display_domain: d,
          extid: `cd_${d.replace(/\./g, '_')}`,
          permissions: {
            can_view: true,
            can_edit: true,
            can_delete: false,
            can_manage_settings: false,
          },
        })),
        assignable_roles: ['member', 'admin'],
      },
    ],
  };
}

/**
 * Build a multi-org BulkPermissionsResponse.
 */
function buildMultiOrgPermissionsResponse(
  orgs: Array<{ extid: string; domains: string[] }>
): BulkPermissionsResponse {
  return {
    organizations: orgs.map((org) => ({
      extid: org.extid,
      display_name: `Org ${org.extid}`,
      is_default: false,
      membership: {
        role: 'owner' as const,
        status: 'active',
        provisioning_source: null,
        invited_at: null,
        joined_at: '2026-01-01',
        entitlements: ['custom_domains'],
      },
      permissions: {
        can_view: true,
        can_edit: true,
        can_delete: false,
        can_manage_settings: true,
      },
      domains: org.domains.map((d) => ({
        display_domain: d,
        extid: `cd_${d.replace(/\./g, '_')}`,
        permissions: {
          can_view: true,
          can_edit: true,
          can_delete: false,
          can_manage_settings: false,
        },
      })),
      assignable_roles: ['member', 'admin'],
    })),
  };
}

/**
 * Helper to configure the permissions mock for a given org.
 * Replaces the old setMockDomains which was synchronous.
 */
function setMockDomains(orgExtid: string, domains: string[]) {
  mockFetchAllPermissions.mockResolvedValue(
    buildPermissionsResponse(orgExtid, domains)
  );
}

describe('useDomainContext', () => {
  const mockSessionStorage = (() => {
    let store: Record<string, string> = {};
    return {
      getItem: (key: string) => store[key] || null,
      setItem: (key: string, value: string) => {
        store[key] = value.toString();
      },
      removeItem: (key: string) => {
        delete store[key];
      },
      clear: () => {
        store = {};
      },
    };
  })();

  /**
   * Helper to set up bootstrapStore with domain configuration
   */
  function setupBootstrapStore(config: {
    domains_enabled?: boolean;
    site_host?: string;
    display_domain?: string;
    custom_domains?: string[];
    domain_strategy?: 'canonical' | 'subdomain' | 'custom' | 'invalid';
  }) {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    setActivePinia(pinia);

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.domains_enabled = config.domains_enabled ?? true;
    bootstrapStore.site_host = config.site_host ?? 'onetimesecret.com';
    bootstrapStore.display_domain = config.display_domain ?? config.site_host ?? 'onetimesecret.com';
    bootstrapStore.custom_domains = config.custom_domains ?? [];
    bootstrapStore.domain_strategy = config.domain_strategy ?? 'canonical';

    return { pinia, bootstrapStore };
  }

  /** Wait for async initialization to complete */
  async function waitForInit() {
    await nextTick();
    await new Promise((r) => setTimeout(r, 10));
  }

  beforeEach(async () => {
    vi.resetModules();
    vi.clearAllMocks();

    mockSessionStorage.clear();
    Object.defineProperty(window, 'sessionStorage', {
      value: mockSessionStorage,
      writable: true,
      configurable: true,
    });

    // Reset mock with default implementation
    mockFetchAllPermissions.mockReset();
    mockFetchAllPermissions.mockResolvedValue({ organizations: [] } as BulkPermissionsResponse);

    // Set a default organization - required for domain context initialization.
    // Both objid (for watcher) and extid (for fetcher) are required.
    mockOrganizationStoreState.currentOrganization = {
      objid: 'org-test-123',
      extid: 'org-ext-test-123',
    };

    const { __resetDomainContextForTesting } = await import(
      '@/shared/composables/useDomainContext'
    );
    __resetDomainContextForTesting();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('initialization', () => {
    it('initializes with canonical domain when no custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // No custom domains in permissions response
      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive, hasMultipleContexts } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.displayName).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expect(isContextActive.value).toBe(true);
      expect(hasMultipleContexts.value).toBe(false);
    });

    it('initializes with first custom domain when custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive, hasMultipleContexts } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.displayName).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
      expect(isContextActive.value).toBe(true);
      expect(hasMultipleContexts.value).toBe(true);
    });

    it('initializes with saved domain from sessionStorage if valid', async () => {
      mockSessionStorage.setItem('domainContext', 'widgets.example.com');

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('widgets.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('ignores invalid saved domain from sessionStorage', async () => {
      mockSessionStorage.setItem('domainContext', 'invalid.example.com');

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      // Should fall back to first available domain
      expect(currentContext.value.domain).toBe('acme.example.com');
    });

    it('handles domains_enabled being false', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { isContextActive } = useDomainContext();

      expect(isContextActive.value).toBe(false);
    });

    it('handles missing custom_domains array', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Empty domains in permissions response
      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(isContextActive.value).toBe(true);
    });
  });

  describe('permissions API data source', () => {
    it('calls fetchAllPermissions, not domainsStore.fetchList', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      useDomainContext();

      await waitForInit();

      expect(mockFetchAllPermissions).toHaveBeenCalled();
    });

    it('extracts domains for the current org extid from the bulk response', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Response has two orgs; composable should extract domains for the current one
      mockFetchAllPermissions.mockResolvedValue(
        buildMultiOrgPermissionsResponse([
          { extid: 'org-ext-test-123', domains: ['my-domain.example.com'] },
          { extid: 'org-ext-other', domains: ['other-domain.example.com'] },
        ])
      );

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains } = useDomainContext();

      await waitForInit();

      // Should only contain domains from the matching org + canonical
      expect(availableDomains.value).toContain('my-domain.example.com');
      expect(availableDomains.value).toContain('onetimesecret.com');
      expect(availableDomains.value).not.toContain('other-domain.example.com');
    });

    it('member-role user without custom_domains entitlement still gets domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Member role, no entitlements -- permissions API still returns domain info
      mockFetchAllPermissions.mockResolvedValue(
        buildPermissionsResponse('org-ext-test-123', ['shared.example.com', 'team.example.com'], {
          role: 'member',
          entitlements: [],
        })
      );

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains, currentContext, hasMultipleContexts } = useDomainContext();

      await waitForInit();

      // Domains should populate regardless of entitlements
      expect(availableDomains.value).toContain('shared.example.com');
      expect(availableDomains.value).toContain('team.example.com');
      expect(hasMultipleContexts.value).toBe(true);
      expect(currentContext.value.domain).toBe('shared.example.com');
    });
  });

  describe('availableDomains', () => {
    it('includes custom domains and canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual([
        'acme.example.com',
        'widgets.example.com',
        'onetimesecret.com',
      ]);
    });

    it('does not duplicate canonical domain if it is in custom_domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['onetimesecret.com', 'acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['onetimesecret.com', 'acme.example.com']);
    });
  });

  describe('currentContext computed properties', () => {
    it('correctly identifies canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      // Start with custom domain
      expect(currentContext.value.isCanonical).toBe(false);
      expect(currentContext.value.displayName).toBe('acme.example.com');

      // Switch to canonical
      setContext('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expect(currentContext.value.displayName).toBe('onetimesecret.com');
    });

    it('sets displayName to domain name for canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.displayName).toBe('onetimesecret.com');
    });

    it('sets displayName to domain for custom domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.displayName).toBe('acme.example.com');
    });
  });

  describe('setContext', () => {
    it('updates currentDomain when valid domain is provided', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      setContext('widgets.example.com');

      expect(currentContext.value.domain).toBe('widgets.example.com');
    });

    it('saves domain to sessionStorage', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { setContext } = useDomainContext();

      await waitForInit();

      setContext('acme.example.com');

      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');
    });

    it('ignores invalid domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      const initialDomain = currentContext.value.domain;

      setContext('invalid.example.com');

      expect(currentContext.value.domain).toBe(initialDomain);
      expect(mockSessionStorage.getItem('domainContext')).toBeNull();
    });

    it('can switch to canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      setContext('onetimesecret.com');

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });
  });

  describe('resetContext', () => {
    it('resets to canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext, resetContext } = useDomainContext();

      await waitForInit();

      // Start with custom domain
      setContext('acme.example.com');
      expect(currentContext.value.domain).toBe('acme.example.com');

      // Reset
      resetContext();
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    it('removes domainContext from sessionStorage', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { setContext, resetContext } = useDomainContext();

      await waitForInit();

      setContext('acme.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');

      resetContext();
      expect(mockSessionStorage.getItem('domainContext')).toBeNull();
    });
  });

  describe('isContextActive computed', () => {
    it('returns false when domains_enabled is false', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { isContextActive } = useDomainContext();

      expect(isContextActive.value).toBe(false);
    });

    it('returns true when domains_enabled even with empty custom_domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { isContextActive } = useDomainContext();

      expect(isContextActive.value).toBe(true);
    });

    it('returns true when domains_enabled even with undefined custom_domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { isContextActive } = useDomainContext();

      expect(isContextActive.value).toBe(true);
    });

    it('returns true when domains enabled and custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { isContextActive } = useDomainContext();

      expect(isContextActive.value).toBe(true);
    });
  });

  describe('hasMultipleContexts computed', () => {
    it('returns false when only canonical domain exists', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { hasMultipleContexts } = useDomainContext();

      await waitForInit();

      expect(hasMultipleContexts.value).toBe(false);
    });

    it('returns true when custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { hasMultipleContexts } = useDomainContext();

      await waitForInit();

      expect(hasMultipleContexts.value).toBe(true);
    });

    it('returns true when multiple custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { hasMultipleContexts } = useDomainContext();

      await waitForInit();

      expect(hasMultipleContexts.value).toBe(true);
    });
  });

  describe('edge cases', () => {
    it('handles empty canonical domain gracefully', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: '',
        display_domain: '',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('acme.example.com');
    });

    it('handles all missing configuration gracefully', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: '',
        display_domain: '',
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive } = useDomainContext();

      expect(currentContext.value.domain).toBe('');
      expect(isContextActive.value).toBe(false);
    });
  });

  describe('organization change handling', () => {
    it('refreshes domain list when organization changes', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Start with domains for org 1
      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-1',
        extid: 'org-ext-1',
      };
      setMockDomains('org-ext-1', ['org1-domain.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('org1-domain.example.com');
      expect(mockFetchAllPermissions).toHaveBeenCalled();
    });

    it('re-extracts domains for new org on refreshDomains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Start with org 1
      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-1',
        extid: 'org-ext-1',
      };
      setMockDomains('org-ext-1', ['org1-domain.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, refreshDomains } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('org1-domain.example.com');

      // Switch to org 2: update both objid and extid, provide new response
      mockFetchAllPermissions.mockResolvedValue(
        buildMultiOrgPermissionsResponse([
          { extid: 'org-ext-1', domains: ['org1-domain.example.com'] },
          { extid: 'org-ext-2', domains: ['org2-domain.example.com', 'org2-other.example.com'] },
        ])
      );
      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-2',
        extid: 'org-ext-2',
      };

      // Simulate what the watcher does: call refreshDomains for the new org
      const result = await refreshDomains();
      expect(result).toBe(true);

      // Domains should now reflect org 2 (extracted by extid match)
      expect(availableDomains.value).toContain('org2-domain.example.com');
      expect(availableDomains.value).toContain('org2-other.example.com');
      expect(availableDomains.value).not.toContain('org1-domain.example.com');
    });

    it('resets to preferred domain when current selection is invalid for new org', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Set up for org 1
      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-1',
        extid: 'org-ext-1',
      };
      setMockDomains('org-ext-1', ['org1-domain.example.com', 'shared-domain.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      // Select org1-specific domain
      setContext('org1-domain.example.com');
      expect(currentContext.value.domain).toBe('org1-domain.example.com');

      // Simulate org switch - org2 has different domains
      mockFetchAllPermissions.mockResolvedValue(
        buildPermissionsResponse('org-ext-2', ['org2-domain.example.com'])
      );
      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-2',
        extid: 'org-ext-2',
      };

      // Wait for watcher to fire
      await nextTick();
      await new Promise((r) => setTimeout(r, 50));

      expect(mockFetchAllPermissions).toHaveBeenCalled();
    });
  });

  describe('extid lookups with permissions data', () => {
    it('getExtidByDomain resolves using permissions-sourced data', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getExtidByDomain } = useDomainContext();

      await waitForInit();

      expect(getExtidByDomain('acme.example.com')).toBe('cd_acme_example_com');
      expect(getExtidByDomain('widgets.example.com')).toBe('cd_widgets_example_com');
      expect(getExtidByDomain('nonexistent.example.com')).toBeUndefined();
    });

    it('getDomainByExtid resolves using permissions-sourced data', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getDomainByExtid } = useDomainContext();

      await waitForInit();

      expect(getDomainByExtid('cd_acme_example_com')).toBe('acme.example.com');
      expect(getDomainByExtid('cd_widgets_example_com')).toBe('widgets.example.com');
      expect(getDomainByExtid('cd_nonexistent')).toBeUndefined();
    });

    it('currentContext.extid is set for custom domain from permissions data', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.extid).toBe('cd_acme_example_com');
    });
  });

  describe('race condition protection', () => {
    it('tracks request IDs to handle superseded fetches', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-1',
        extid: 'org-ext-1',
      };
      setMockDomains('org-ext-1', ['initial-domain.example.com']);

      // Track fetch calls with deferred promises
      let fetchCallCount = 0;
      type DeferredFetch = {
        resolve: (v: BulkPermissionsResponse | null) => void;
        promise: Promise<BulkPermissionsResponse | null>;
      };
      const fetchPromises: DeferredFetch[] = [];

      mockFetchAllPermissions.mockImplementation(() => {
        fetchCallCount++;
        let resolveRef: (v: BulkPermissionsResponse | null) => void;
        const promise = new Promise<BulkPermissionsResponse | null>((resolve) => {
          resolveRef = resolve;
        });
        fetchPromises.push({ resolve: resolveRef!, promise });
        return promise;
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { refreshDomains } = useDomainContext();

      // Wait for initialization watcher to trigger
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Reset mock to track only our explicit calls
      fetchCallCount = 0;
      fetchPromises.length = 0;

      // Start first fetch
      const fetch1Promise = refreshDomains();
      await nextTick();

      // Start second fetch before first completes (rapid org switch simulation)
      const fetch2Promise = refreshDomains();
      await nextTick();

      expect(fetchCallCount).toBe(2);

      const response = buildPermissionsResponse('org-ext-1', ['initial-domain.example.com']);

      // Complete both fetches
      fetchPromises[0]?.resolve(response);
      fetchPromises[1]?.resolve(response);

      const [result1, result2] = await Promise.all([fetch1Promise, fetch2Promise]);

      // First request should return false (superseded/aborted)
      // Second request should return true (current)
      expect(result1).toBe(false);
      expect(result2).toBe(true);
    });

    it('returns false when no organization is set', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // No organization set
      mockOrganizationStoreState.currentOrganization = null;

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { refreshDomains } = useDomainContext();

      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      const result = await refreshDomains();

      // Should return false when no org is set (guard clause)
      expect(result).toBe(false);
    });

    it('handles fetch errors gracefully', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      mockOrganizationStoreState.currentOrganization = {
        objid: 'org-1',
        extid: 'org-ext-1',
      };
      setMockDomains('org-ext-1', ['test-domain.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { refreshDomains, isLoadingDomains } = useDomainContext();

      await waitForInit();

      // Now make fetch fail
      mockFetchAllPermissions.mockRejectedValue(new Error('Network error'));

      const result = await refreshDomains();

      // Should return false on error
      expect(result).toBe(false);
      // Loading should be cleared after error
      expect(isLoadingDomains.value).toBe(false);
    });
  });

  describe('getPreferredDomain behavior', () => {
    it('prefers custom domain over canonical when custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('falls back to canonical when no custom domains available', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expect(availableDomains.value).toContain('onetimesecret.com');
    });

    it('prefers first custom domain when multiple custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['zebra.example.com', 'alpha.example.com', 'beta.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      // Should select first in array order, not alphabetical
      expect(currentContext.value.domain).toBe('zebra.example.com');
    });

    it('handles array with only canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['onetimesecret.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    it('skips canonical in the list when selecting preferred domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['onetimesecret.com', 'custom.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('custom.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('returns empty string when no domains available and no canonical', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: '',
        display_domain: '',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('');
    });
  });

  describe('setContext backend sync behavior', () => {
    let mockApiPost: ReturnType<typeof vi.fn>;
    let mockApi: { post: ReturnType<typeof vi.fn> };

    beforeEach(() => {
      mockApiPost = vi.fn().mockResolvedValue({ data: {} });
      mockApi = { post: mockApiPost };
    });

    async function importWithMockApi() {
      const vue = await import('vue');
      const originalInject = vue.inject;
      vi.spyOn(vue, 'inject').mockImplementation((key: any, ...args: any[]) => {
        if (key === 'api') return mockApi;
        return (originalInject as any)(key, ...args);
      });

      const mod = await import('@/shared/composables/useDomainContext');
      return mod;
    }

    it('selecting a custom domain triggers POST to update-domain-context', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      await setContext('acme.example.com');

      expect(mockApiPost).toHaveBeenCalledWith(
        '/api/account/update-domain-context',
        { domain: 'acme.example.com' }
      );
    });

    it('selecting a custom domain stores value in sessionStorage', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      await setContext('acme.example.com');

      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');
    });

    it('selecting canonical domain should NOT trigger backend sync POST', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      // Clear any calls from initialization
      mockApiPost.mockClear();

      await setContext('onetimesecret.com');

      // No POST should have been made for canonical domain
      expect(mockApiPost).not.toHaveBeenCalled();
    });

    it('selecting canonical domain should clear sessionStorage domainContext', async () => {
      mockSessionStorage.setItem('domainContext', 'acme.example.com');

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      await setContext('onetimesecret.com');

      // Canonical is the default state -- session storage should be cleared
      expect(mockSessionStorage.getItem('domainContext')).toBeNull();
    });

    it('selecting canonical domain updates currentContext correctly', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext, currentContext } = useDomainContext();

      await waitForInit();

      await setContext('onetimesecret.com');

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expect(currentContext.value.extid).toBeUndefined();
    });

    it('selecting canonical domain does not throw even if server would return 422', async () => {
      mockApiPost.mockRejectedValue({
        response: { status: 422, data: { message: 'Invalid domain' } },
      });

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      await expect(setContext('onetimesecret.com')).resolves.toBeUndefined();
    });

    it('skipBackendSync=true prevents POST even for custom domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      mockApiPost.mockClear();

      await setContext('acme.example.com', true);

      expect(mockApiPost).not.toHaveBeenCalled();
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');
    });
  });

  describe('setContext error handling (sync failures)', () => {
    let mockApiPost: ReturnType<typeof vi.fn>;
    let mockApi: { post: ReturnType<typeof vi.fn> };

    beforeEach(() => {
      mockApiPost = vi.fn().mockResolvedValue({ data: {} });
      mockApi = { post: mockApiPost };
    });

    async function importWithMockApi() {
      const vue = await import('vue');
      const originalInject = vue.inject;
      vi.spyOn(vue, 'inject').mockImplementation((key: any, ...args: any[]) => {
        if (key === 'api') return mockApi;
        return (originalInject as any)(key, ...args);
      });
      return import('@/shared/composables/useDomainContext');
    }

    it('catches network errors from syncDomainContextToServer without throwing', async () => {
      mockApiPost.mockRejectedValue(new Error('Network Error'));

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      const { useDomainContext } = await importWithMockApi();
      const { setContext } = useDomainContext();

      await waitForInit();

      // Should not throw
      await expect(setContext('acme.example.com')).resolves.toBeUndefined();

      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('[useDomainContext]'),
        expect.anything()
      );

      warnSpy.mockRestore();
    });

    it('catches 422 responses gracefully and still updates local state', async () => {
      mockApiPost.mockRejectedValue({
        response: { status: 422, data: { message: 'Invalid domain' } },
      });

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      const { useDomainContext } = await importWithMockApi();
      const { setContext, currentContext } = useDomainContext();

      await waitForInit();

      await setContext('acme.example.com');

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');

      warnSpy.mockRestore();
    });

    it('sync failure does not revert currentDomain', async () => {
      mockApiPost.mockRejectedValue(new Error('500 Internal Server Error'));

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      const { useDomainContext } = await importWithMockApi();
      const { setContext, currentContext } = useDomainContext();

      await waitForInit();

      await setContext('widgets.example.com');

      expect(currentContext.value.domain).toBe('widgets.example.com');

      warnSpy.mockRestore();
    });
  });

  describe('ghost domain fallback', () => {
    it('falls back to preferred domain when serverDomainContext is not in available domains', async () => {
      const { bootstrapStore } = setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Server references a domain that was removed (ghost domain)
      bootstrapStore.domain_context = 'deleted-domain.example.com';

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      // Should skip the ghost domain and fall back to preferred (first custom)
      expect(currentContext.value.domain).not.toBe('deleted-domain.example.com');
      expect(currentContext.value.domain).toBe('acme.example.com');
    });

    it('falls back when both serverDomainContext and sessionStorage reference removed domain', async () => {
      mockSessionStorage.setItem('domainContext', 'removed-domain.example.com');

      const { bootstrapStore } = setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });
      bootstrapStore.domain_context = 'removed-domain.example.com';

      setMockDomains('org-ext-test-123', ['surviving.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('surviving.example.com');
      expect(currentContext.value.domain).not.toBe('removed-domain.example.com');
    });
  });
});
