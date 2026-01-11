// src/tests/composables/useDomainScope.spec.ts

import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { nextTick } from 'vue';

// Create mock stores before vi.mock calls
const mockDomainsStoreState = {
  domains: [] as Array<{ display_domain: string }>,
  fetchList: vi.fn().mockResolvedValue(undefined),
};

const mockOrganizationStoreState = {
  currentOrganization: null as { id: string } | null,
};

// Mock WindowService
vi.mock('@/services/window.service', () => ({
  WindowService: {
    getMultiple: vi.fn(),
  },
}));

// Mock stores
vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => mockDomainsStoreState,
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrganizationStoreState,
}));

// Import WindowService after mocks
import { WindowService } from '@/services/window.service';

/**
 * Helper to set up domains store mock
 */
function setMockDomains(domains: string[]) {
  mockDomainsStoreState.domains = domains.map((d) => ({ display_domain: d }));
}

describe('useDomainScope', () => {
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
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // No custom domains in store
      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive, hasMultipleScopes } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(currentScope.value.displayName).toBe('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
      expect(isScopeActive.value).toBe(true);
      expect(hasMultipleScopes.value).toBe(false);
    });

    it('initializes with first custom domain when custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Set custom domains in store
      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive, hasMultipleScopes } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.domain).toBe('acme.example.com');
      expect(currentScope.value.displayName).toBe('acme.example.com');
      expect(currentScope.value.isCanonical).toBe(false);
      expect(isScopeActive.value).toBe(true);
      expect(hasMultipleScopes.value).toBe(true);
    });

    it('initializes with saved domain from localStorage if valid', async () => {
      mockLocalStorage.setItem('domainScope', 'widgets.example.com');

      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.domain).toBe('widgets.example.com');
      expect(currentScope.value.isCanonical).toBe(false);
    });

    it('ignores invalid saved domain from localStorage', async () => {
      mockLocalStorage.setItem('domainScope', 'invalid.example.com');

      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should fall back to first available domain
      expect(currentScope.value.domain).toBe('acme.example.com');
    });

    it('handles domains_enabled being false', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(false);
    });

    it('handles missing custom_domains array', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Empty domains
      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(isScopeActive.value).toBe(true);
    });
  });

  describe('availableDomains', () => {
    it('includes custom domains and canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { availableDomains } = useDomainScope();

      expect(availableDomains.value).toEqual([
        'acme.example.com',
        'widgets.example.com',
        'onetimesecret.com',
      ]);
    });

    it('does not duplicate canonical domain if it is in custom_domains', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['onetimesecret.com', 'acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { availableDomains } = useDomainScope();

      expect(availableDomains.value).toEqual(['onetimesecret.com', 'acme.example.com']);
    });
  });

  describe('currentScope computed properties', () => {
    it('correctly identifies canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Start with custom domain
      expect(currentScope.value.isCanonical).toBe(false);
      expect(currentScope.value.displayName).toBe('acme.example.com');

      // Switch to canonical
      setScope('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
      expect(currentScope.value.displayName).toBe('onetimesecret.com');
    });

    it('sets displayName to domain name for canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.displayName).toBe('onetimesecret.com');
    });

    it('sets displayName to domain for custom domains', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.displayName).toBe('acme.example.com');
    });
  });

  describe('setScope', () => {
    it('updates currentDomain when valid domain is provided', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setScope('widgets.example.com');

      expect(currentScope.value.domain).toBe('widgets.example.com');
    });

    it('saves domain to localStorage', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { setScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setScope('acme.example.com');

      expect(mockLocalStorage.getItem('domainScope')).toBe('acme.example.com');
    });

    it('ignores invalid domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      const initialDomain = currentScope.value.domain;

      setScope('invalid.example.com');

      expect(currentScope.value.domain).toBe(initialDomain);
      expect(mockLocalStorage.getItem('domainScope')).toBeNull();
    });

    it('can switch to canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setScope('onetimesecret.com');

      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
    });
  });

  describe('resetScope', () => {
    it('resets to canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope, resetScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Start with custom domain
      setScope('acme.example.com');
      expect(currentScope.value.domain).toBe('acme.example.com');

      // Reset
      resetScope();
      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
    });

    it('removes domainScope from localStorage', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { setScope, resetScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      setScope('acme.example.com');
      expect(mockLocalStorage.getItem('domainScope')).toBe('acme.example.com');

      resetScope();
      expect(mockLocalStorage.getItem('domainScope')).toBeNull();
    });
  });

  describe('isScopeActive computed', () => {
    it('returns false when domains_enabled is false', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(false);
    });

    it('returns true when domains_enabled even with empty custom_domains', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(true);
    });

    it('returns true when domains_enabled even with undefined custom_domains', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Set domains to empty (simulating undefined)
      mockDomainsStoreState.domains = [];

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(true);
    });

    it('returns true when domains enabled and custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(true);
    });
  });

  describe('hasMultipleScopes computed', () => {
    it('returns false when only canonical domain exists', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { hasMultipleScopes } = useDomainScope();

      expect(hasMultipleScopes.value).toBe(false);
    });

    it('returns true when custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { hasMultipleScopes } = useDomainScope();

      expect(hasMultipleScopes.value).toBe(true);
    });

    it('returns true when multiple custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { hasMultipleScopes } = useDomainScope();

      expect(hasMultipleScopes.value).toBe(true);
    });
  });

  describe('edge cases', () => {
    it('handles empty canonical domain gracefully', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: '',
        display_domain: '',
      });

      setMockDomains(['acme.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      expect(currentScope.value.domain).toBe('acme.example.com');
    });

    it('handles all missing configuration gracefully', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: false,
        site_host: undefined,
        display_domain: undefined,
      });

      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive } = useDomainScope();

      expect(currentScope.value.domain).toBe('');
      expect(isScopeActive.value).toBe(false);
    });
  });

  describe('getPreferredDomain behavior', () => {
    it('prefers custom domain over canonical when custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Set custom domains - first non-canonical should be preferred
      setMockDomains(['acme.example.com', 'widgets.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should select first custom domain, not canonical
      expect(currentScope.value.domain).toBe('acme.example.com');
      expect(currentScope.value.isCanonical).toBe(false);
    });

    it('falls back to canonical when no custom domains available', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // No custom domains - only canonical available
      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, availableDomains } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should fall back to canonical
      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
      // Available domains should include canonical even when no custom domains
      expect(availableDomains.value).toContain('onetimesecret.com');
    });

    it('prefers first custom domain when multiple custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Multiple custom domains - first should be selected
      setMockDomains(['zebra.example.com', 'alpha.example.com', 'beta.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should select first in array order, not alphabetical
      expect(currentScope.value.domain).toBe('zebra.example.com');
    });

    it('handles array with only canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Only canonical domain in the list
      setMockDomains(['onetimesecret.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // No custom domains to prefer, should use canonical
      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
    });

    it('skips canonical in the list when selecting preferred domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      // Canonical appears first but should be skipped for a custom domain
      setMockDomains(['onetimesecret.com', 'custom.example.com']);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // Should skip canonical and prefer custom domain
      expect(currentScope.value.domain).toBe('custom.example.com');
      expect(currentScope.value.isCanonical).toBe(false);
    });

    it('returns empty string when no domains available and no canonical', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: '',
        display_domain: '',
      });

      setMockDomains([]);

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Wait for async initialization
      await nextTick();
      await new Promise((r) => setTimeout(r, 10));

      // With no domains at all, should be empty
      expect(currentScope.value.domain).toBe('');
    });
  });
});
