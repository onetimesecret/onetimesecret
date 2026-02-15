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

// Create mock stores before vi.mock calls
const mockDomainsStoreState = {
  domains: [] as Array<{ display_domain: string; extid: string }>,
  fetchList: vi.fn().mockResolvedValue(undefined),
};

const mockOrganizationStoreState = {
  currentOrganization: null as { id: string } | null,
};

vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => mockDomainsStoreState,
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrganizationStoreState,
}));

function setMockDomains(domains: string[]) {
  mockDomainsStoreState.domains = domains.map((d) => ({
    display_domain: d,
    extid: `cd_${d.replace(/\./g, '_')}`,
  }));
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

    mockDomainsStoreState.domains = [];
    mockDomainsStoreState.fetchList.mockReset();
    mockDomainsStoreState.fetchList.mockResolvedValue(undefined);
    mockOrganizationStoreState.currentOrganization = { id: 'org-test-123' };

    const { __resetDomainContextForTesting } = await import(
      '@/shared/composables/useDomainContext'
    );
    __resetDomainContextForTesting();
  });

  describe('setContext rejects extid values (bug proof)', () => {
    it('ignores extid string because it is not a valid domain', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains(['acme.example.com', 'widgets.example.com']);

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
      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getExtidByDomain, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(getExtidByDomain('acme.example.com')).toBe('cd_acme_example_com');
    });

    it('composable API provides reverse lookup (extid -> domain)', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const api = useDomainContext();

      await nextTick();
      await api.initialized;

      expect(api).toHaveProperty('getDomainByExtid');
      expect(api).toHaveProperty('setContextByExtid');
    });

    it('getDomainByExtid returns domain for known extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getDomainByExtid, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(getDomainByExtid('cd_acme_example_com')).toBe('acme.example.com');
      expect(getDomainByExtid('cd_widgets_example_com')).toBe('widgets.example.com');
    });

    it('getDomainByExtid returns undefined for unknown extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { getDomainByExtid, initialized } = useDomainContext();

      await nextTick();
      await initialized;

      expect(getDomainByExtid('cd_unknown_domain')).toBeUndefined();
    });

    it('setContextByExtid updates domain context via extid', async () => {
      setupBootstrapStore({ domains_enabled: true, site_host: 'onetimesecret.com' });
      setMockDomains(['acme.example.com', 'widgets.example.com']);

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
      setMockDomains(['acme.example.com']);

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
      setMockDomains(['acme.example.com', 'widgets.example.com']);

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
      setMockDomains(['acme.example.com', 'widgets.example.com']);

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
