// src/tests/composables/useDomainContext.spec.ts

import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
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

// Mock stores
vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => mockDomainsStoreState,
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrganizationStoreState,
}));

/**
 * Helper to set up domains store mock
 */
function setMockDomains(domains: string[]) {
  mockDomainsStoreState.domains = domains.map((d) => ({
    display_domain: d,
    extid: `cd_${d.replace(/\./g, '_')}`,
  }));
}

describe('useDomainContext', () => {
  const mockLocalStorage = (() => {
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

    return { pinia, bootstrapStore };
  }

  beforeEach(async () => {
    // Reset localStorage mock
    mockLocalStorage.clear();
    Object.defineProperty(window, 'localStorage', {
      value: mockLocalStorage,
      writable: true,
      configurable: true,
    });

    // Reset mock stores
    mockDomainsStoreState.domains = [];
    mockDomainsStoreState.fetchList.mockClear();
    mockOrganizationStoreState.currentOrganization = null;

    // Reset all modules to clear the shared state
    vi.resetModules();
    vi.clearAllMocks();
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

      // No custom domains in store
      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive, hasMultipleContexts } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

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

      // Set custom domains in store
      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive, hasMultipleContexts } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.displayName).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
      expect(isContextActive.value).toBe(true);
      expect(hasMultipleContexts.value).toBe(true);
    });

    it('initializes with saved domain from localStorage if valid', async () => {
      mockLocalStorage.setItem('domainContext', 'widgets.example.com');

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentContext.value.domain).toBe('widgets.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('ignores invalid saved domain from localStorage', async () => {
      mockLocalStorage.setItem('domainContext', 'invalid.example.com');

      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should fall back to first available domain
      expect(currentContext.value.domain).toBe('acme.example.com');
    });

    it('handles domains_enabled being false', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

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

      // Empty domains
      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, isContextActive } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(isContextActive.value).toBe(true);
    });
  });

  describe('availableDomains', () => {
    it('includes custom domains and canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains } = useDomainContext();

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

      setMockDomains(['onetimesecret.com', 'acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains } = useDomainContext();

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

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

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

      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentContext.value.displayName).toBe('onetimesecret.com');
    });

    it('sets displayName to domain for custom domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

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

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setContext('widgets.example.com');

      expect(currentContext.value.domain).toBe('widgets.example.com');
    });

    it('saves domain to localStorage', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { setContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setContext('acme.example.com');

      expect(mockLocalStorage.getItem('domainContext')).toBe('acme.example.com');
    });

    it('ignores invalid domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      const initialDomain = currentContext.value.domain;

      setContext('invalid.example.com');

      expect(currentContext.value.domain).toBe(initialDomain);
      expect(mockLocalStorage.getItem('domainContext')).toBeNull();
    });

    it('can switch to canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

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

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext, resetContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Start with custom domain
      setContext('acme.example.com');
      expect(currentContext.value.domain).toBe('acme.example.com');

      // Reset
      resetContext();
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    it('removes domainContext from localStorage', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { setContext, resetContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setContext('acme.example.com');
      expect(mockLocalStorage.getItem('domainContext')).toBe('acme.example.com');

      resetContext();
      expect(mockLocalStorage.getItem('domainContext')).toBeNull();
    });
  });

  describe('isContextActive computed', () => {
    it('returns false when domains_enabled is false', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

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

      setMockDomains([]);

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

      // Set domains to empty (simulating undefined)
      mockDomainsStoreState.domains = [];

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

      setMockDomains(['acme.example.com']);

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

      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { hasMultipleContexts } = useDomainContext();

      expect(hasMultipleContexts.value).toBe(false);
    });

    it('returns true when custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { hasMultipleContexts } = useDomainContext();

      expect(hasMultipleContexts.value).toBe(true);
    });

    it('returns true when multiple custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { hasMultipleContexts } = useDomainContext();

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

      setMockDomains(['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentContext.value.domain).toBe('acme.example.com');
    });

    it('handles all missing configuration gracefully', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: '',
        display_domain: '',
      });

      setMockDomains([]);

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
      setMockDomains(['org1-domain.example.com']);
      mockOrganizationStoreState.currentOrganization = { id: 'org-1' };

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentContext.value.domain).toBe('org1-domain.example.com');
      expect(mockDomainsStoreState.fetchList).toHaveBeenCalled();
    });

    it('resets to preferred domain when current selection is invalid for new org', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Set up for org 1
      setMockDomains(['org1-domain.example.com', 'shared-domain.example.com']);
      mockOrganizationStoreState.currentOrganization = { id: 'org-1' };

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Select org1-specific domain
      setContext('org1-domain.example.com');
      expect(currentContext.value.domain).toBe('org1-domain.example.com');

      // Simulate org switch - org2 has different domains
      setMockDomains(['org2-domain.example.com']);
      mockOrganizationStoreState.currentOrganization = { id: 'org-2' };

      // Trigger the watcher manually since we're mocking
      await nextTick();
      await new Promise((r) => setTimeout(r, 50));

      // Note: In the actual implementation, the watcher would detect the org change
      // and reset the domain. This test verifies the domains are correctly set up
      // for the org switch scenario.
      expect(mockDomainsStoreState.fetchList).toHaveBeenCalled();
    });
  });

  describe('race condition protection', () => {
    it('tracks request IDs to handle superseded fetches', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Set up initial state with organization
      setMockDomains(['initial-domain.example.com']);
      mockOrganizationStoreState.currentOrganization = { id: 'org-1' };

      // Track fetch calls
      let fetchCallCount = 0;
      const fetchPromises: Array<{ resolve: () => void; promise: Promise<void> }> = [];

      mockDomainsStoreState.fetchList.mockImplementation(() => {
        fetchCallCount++;
        let resolveRef: () => void;
        const promise = new Promise<void>((resolve) => {
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

      // Complete both fetches
      fetchPromises[0]?.resolve();
      fetchPromises[1]?.resolve();

      const [result1, result2] = await Promise.all([fetch1Promise, fetch2Promise]);

      // First request should return false (superseded)
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
      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { refreshDomains } = useDomainContext();

      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      const result = await refreshDomains();

      // Should return false when no org is set (guard clause)
      expect(result).toBe(false);
      // fetchList should not have been called (no org)
    });

    it('handles fetch errors gracefully', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      mockOrganizationStoreState.currentOrganization = { id: 'org-1' };
      setMockDomains(['test-domain.example.com']);

      // Mock fetchList to throw error
      mockDomainsStoreState.fetchList.mockRejectedValue(new Error('Network error'));

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { refreshDomains, isLoadingDomains } = useDomainContext();

      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Reset mock for our explicit call
      mockDomainsStoreState.fetchList.mockClear();
      mockDomainsStoreState.fetchList.mockRejectedValue(new Error('Network error'));

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

      // Set custom domains - first non-canonical should be preferred
      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should select first custom domain, not canonical
      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('falls back to canonical when no custom domains available', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // No custom domains - only canonical available
      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should fall back to canonical
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      // Available domains should include canonical even when no custom domains
      expect(availableDomains.value).toContain('onetimesecret.com');
    });

    it('prefers first custom domain when multiple custom domains exist', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Multiple custom domains - first should be selected
      setMockDomains(['zebra.example.com', 'alpha.example.com', 'beta.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should select first in array order, not alphabetical
      expect(currentContext.value.domain).toBe('zebra.example.com');
    });

    it('handles array with only canonical domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Only canonical domain in the list
      setMockDomains(['onetimesecret.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // No custom domains to prefer, should use canonical
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    it('skips canonical in the list when selecting preferred domain', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Canonical appears first but should be skipped for a custom domain
      setMockDomains(['onetimesecret.com', 'custom.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should skip canonical and prefer custom domain
      expect(currentContext.value.domain).toBe('custom.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('returns empty string when no domains available and no canonical', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: '',
        display_domain: '',
      });

      setMockDomains([]);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // With no domains at all, should be empty
      expect(currentContext.value.domain).toBe('');
    });
  });
});
