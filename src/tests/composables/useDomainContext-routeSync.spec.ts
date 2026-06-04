// src/tests/composables/useDomainContext-routeSync.spec.ts
/**
 * Tests for domain context route synchronization.
 *
 * Verifies that:
 * 1. setContext() correctly rejects extid strings (not domain names)
 * 2. getDomainByExtid provides reverse lookup (extid -> domain)
 * 3. setContextByExtid bridges route params to domain context
 * 4. Manual setContext still works for direct domain selection
 *
 * @see src/shared/composables/useDomainContext.ts
 * @see src/shared/components/navigation/DomainContextSwitcher.vue
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
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
  domains: string[]
): BulkPermissionsResponse {
  return {
    organizations: [
      {
        extid: orgExtid,
        display_name: `Org ${orgExtid}`,
        is_default: true,
        membership: {
          role: 'owner',
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

/** Configure the permissions mock with domains for the test org. */
function setMockDomains(orgExtid: string, domains: string[]) {
  mockFetchAllPermissions.mockResolvedValue(buildPermissionsResponse(orgExtid, domains));
}

describe('useDomainContext route synchronization', () => {
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

  function setupBootstrapStore(config: {
    domains_enabled?: boolean;
    site_host?: string;
    display_domain?: string;
  }) {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    setActivePinia(pinia);

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.domains_enabled = config.domains_enabled ?? true;
    bootstrapStore.site_host = config.site_host ?? 'onetimesecret.com';
    bootstrapStore.display_domain =
      config.display_domain ?? config.site_host ?? 'onetimesecret.com';

    return { pinia, bootstrapStore };
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

    mockFetchAllPermissions.mockReset();
    mockFetchAllPermissions.mockResolvedValue({ organizations: [] } as BulkPermissionsResponse);
    mockOrganizationStoreState.currentOrganization = {
      objid: 'org-test-123',
      extid: 'org-ext-test-123',
    };

    const { __resetDomainContextForTesting } = await import(
      '@/shared/composables/useDomainContext'
    );
    __resetDomainContextForTesting();
  });

  describe('setContext rejects extid values (bug proof)', () => {
    it('ignores extid string because it is not a valid domain', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      const initialDomain = currentContext.value.domain;

      await setContext('cd_widgets_example_com');

      expect(currentContext.value.domain).toBe(initialDomain);
    });
  });

  describe('reverse lookup (extid -> domain)', () => {
    it('getExtidByDomain provides domain-to-extid lookup', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getExtidByDomain, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(getExtidByDomain('acme.example.com')).toBe('cd_acme_example_com');
    });

    it('composable API provides reverse lookup (extid -> domain)', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const api = useDomainContext();

      await nextTick();
      await api.initialized;

      expect(api).toHaveProperty('getDomainByExtid');
      expect(api).toHaveProperty('setContextByExtid');
    });

    it('getDomainByExtid returns domain for known extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getDomainByExtid, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(getDomainByExtid('cd_acme_example_com')).toBe('acme.example.com');
      expect(getDomainByExtid('cd_widgets_example_com')).toBe('widgets.example.com');
    });

    it('getDomainByExtid returns undefined for unknown extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getDomainByExtid, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(getDomainByExtid('cd_unknown_domain')).toBeUndefined();
    });

    it('setContextByExtid updates domain context via extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContextByExtid, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(currentContext.value.domain).toBe('acme.example.com');

      await setContextByExtid('cd_widgets_example_com');
      expect(currentContext.value.domain).toBe('widgets.example.com');
    });

    it('setContextByExtid does nothing for unknown extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContextByExtid, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      const initialDomain = currentContext.value.domain;
      await setContextByExtid('cd_unknown_domain');
      expect(currentContext.value.domain).toBe(initialDomain);
    });
  });

  describe('no route awareness in composable', () => {
    it('domain stays at initial value regardless of external state changes', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(currentContext.value.domain).toBe('acme.example.com');

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.domain).not.toBe('widgets.example.com');
    });

    it('only manual setContext call updates the domain', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(currentContext.value.domain).toBe('acme.example.com');

      await setContext('widgets.example.com');
      expect(currentContext.value.domain).toBe('widgets.example.com');
    });
  });
});
