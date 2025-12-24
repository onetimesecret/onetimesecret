// src/tests/composables/useDomainScope.spec.ts

import { WindowService } from '@/services/window.service';
import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';

// Mock WindowService
vi.mock('@/services/window.service', () => ({
  WindowService: {
    getMultiple: vi.fn(),
  },
}));

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
        custom_domains: [],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive, hasMultipleScopes } = useDomainScope();

      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(currentScope.value.displayName).toBe('Personal');
      expect(currentScope.value.isCanonical).toBe(true);
      expect(isScopeActive.value).toBe(false); // No custom domains
      expect(hasMultipleScopes.value).toBe(false);
    });

    it('initializes with first custom domain when custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive, hasMultipleScopes } = useDomainScope();

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
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      expect(currentScope.value.domain).toBe('widgets.example.com');
      expect(currentScope.value.isCanonical).toBe(false);
    });

    it('ignores invalid saved domain from localStorage', async () => {
      mockLocalStorage.setItem('domainScope', 'invalid.example.com');

      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      // Should fall back to first available domain
      expect(currentScope.value.domain).toBe('acme.example.com');
    });

    it('handles domains_enabled being false', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: false,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(false);
    });

    it('handles missing custom_domains array', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: undefined,
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive } = useDomainScope();

      expect(currentScope.value.domain).toBe('onetimesecret.com');
      expect(isScopeActive.value).toBe(false);
    });
  });

  describe('availableDomains', () => {
    it('includes custom domains and canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

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
        custom_domains: ['onetimesecret.com', 'acme.example.com'],
      });

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
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

      // Start with custom domain
      expect(currentScope.value.isCanonical).toBe(false);
      expect(currentScope.value.displayName).toBe('acme.example.com');

      // Switch to canonical
      setScope('onetimesecret.com');
      expect(currentScope.value.isCanonical).toBe(true);
      expect(currentScope.value.displayName).toBe('Personal');
    });

    it('sets displayName to "Personal" for canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: [],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      expect(currentScope.value.displayName).toBe('Personal');
    });

    it('sets displayName to domain for custom domains', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      expect(currentScope.value.displayName).toBe('acme.example.com');
    });
  });

  describe('setScope', () => {
    it('updates currentDomain when valid domain is provided', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

      setScope('widgets.example.com');

      expect(currentScope.value.domain).toBe('widgets.example.com');
    });

    it('saves domain to localStorage', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { setScope } = useDomainScope();

      setScope('acme.example.com');

      expect(mockLocalStorage.getItem('domainScope')).toBe('acme.example.com');
    });

    it('ignores invalid domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();
      const initialDomain = currentScope.value.domain;

      setScope('invalid.example.com');

      expect(currentScope.value.domain).toBe(initialDomain);
      expect(mockLocalStorage.getItem('domainScope')).toBeNull();
    });

    it('can switch to canonical domain', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope } = useDomainScope();

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
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, setScope, resetScope } = useDomainScope();

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
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { setScope, resetScope } = useDomainScope();

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
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(false);
    });

    it('returns false when custom_domains is empty', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: [],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(false);
    });

    it('returns false when custom_domains is undefined', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: undefined,
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { isScopeActive } = useDomainScope();

      expect(isScopeActive.value).toBe(false);
    });

    it('returns true when domains enabled and custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

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
        custom_domains: [],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { hasMultipleScopes } = useDomainScope();

      expect(hasMultipleScopes.value).toBe(false);
    });

    it('returns true when custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { hasMultipleScopes } = useDomainScope();

      expect(hasMultipleScopes.value).toBe(true);
    });

    it('returns true when multiple custom domains exist', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

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
        custom_domains: ['acme.example.com'],
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope } = useDomainScope();

      expect(currentScope.value.domain).toBe('acme.example.com');
    });

    it('handles all missing configuration gracefully', async () => {
      vi.mocked(WindowService.getMultiple).mockReturnValue({
        domains_enabled: false,
        site_host: undefined,
        custom_domains: undefined,
      });

      const { useDomainScope } = await import('@/shared/composables/useDomainScope');
      const { currentScope, isScopeActive } = useDomainScope();

      expect(currentScope.value.domain).toBe('');
      expect(isScopeActive.value).toBe(false);
    });
  });
});
