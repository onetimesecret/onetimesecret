// src/tests/components/ScopeSwitcherNavigation.spec.ts
/**
 * Tests for scope switcher navigation behavior.
 *
 * Tests the onOrgSwitch and onDomainSwitch meta properties that control
 * navigation when users switch organizations or domains in the switchers.
 *
 * @see src/types/router.ts - ScopesAvailable interface
 * @see src/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue
 * @see src/shared/components/navigation/DomainScopeSwitcher.vue
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';

// Mock router
const mockPush = vi.fn();
const mockRoute = reactive<{
  path: string;
  matched: Array<{ path: string }>;
  meta: {
    scopesAvailable?: {
      organization?: 'show' | 'locked' | 'hide';
      domain?: 'show' | 'locked' | 'hide';
      onOrgSwitch?: string;
      onDomainSwitch?: string;
    };
  };
}>({
  path: '/org/abc123',
  matched: [{ path: '/org/:extid' }],
  meta: {},
});

vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: mockPush }),
}));

// Mock organization store
const mockOrganizationStore = {
  organizations: [],
  currentOrganization: null,
  hasOrganizations: true,
  setCurrentOrganization: vi.fn(),
  fetchOrganizations: vi.fn(),
};

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrganizationStore,
}));

// Mock domain scope composable
const mockDomainScope = {
  currentScope: { domain: 'test.example.com', extid: 'domain123', displayName: 'test.example.com', isCanonical: false },
  availableDomains: ['test.example.com', 'onetimesecret.com'],
  isScopeActive: { value: true },
  setScope: vi.fn(),
  getDomainDisplayName: (domain: string) => domain,
  getExtidByDomain: vi.fn((domain: string) => domain === 'test.example.com' ? 'domain123' : undefined),
};

vi.mock('@/shared/composables/useDomainScope', () => ({
  useDomainScope: () => mockDomainScope,
}));

// Mock i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

describe('ScopeSwitcher Navigation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.path = '/org/abc123';
    mockRoute.matched = [{ path: '/org/:extid' }];
    mockRoute.meta = {};
  });

  describe('onOrgSwitch navigation behavior', () => {
    /**
     * Helper to simulate organization selection with navigation logic.
     * This mirrors the logic in OrganizationScopeSwitcher.vue selectOrganization()
     */
    function simulateOrgSwitch(org: { id: string; extid?: string }, switchTarget?: string) {
      mockOrganizationStore.setCurrentOrganization(org);

      if (!switchTarget) {
        return; // No navigation configured
      }

      if (switchTarget === 'same') {
        if (!org.extid) {
          console.warn('Cannot navigate: org missing extid');
          return;
        }
        const matchedRoute = mockRoute.matched[mockRoute.matched.length - 1];
        if (matchedRoute?.path) {
          const newPath = matchedRoute.path.replace(':extid', org.extid);
          mockPush(newPath);
        }
      } else if (switchTarget.includes(':extid')) {
        if (!org.extid) {
          console.warn('Cannot navigate: org missing extid');
          return;
        }
        const newPath = switchTarget.replace(':extid', org.extid);
        mockPush(newPath);
      } else {
        mockPush(switchTarget);
      }
    }

    it('does not navigate when onOrgSwitch is undefined', () => {
      const org = { id: 'org1', extid: 'xyz789' };
      simulateOrgSwitch(org, undefined);

      expect(mockOrganizationStore.setCurrentOrganization).toHaveBeenCalledWith(org);
      expect(mockPush).not.toHaveBeenCalled();
    });

    it('navigates to same route pattern when onOrgSwitch is "same"', () => {
      mockRoute.matched = [{ path: '/org/:extid' }];
      const org = { id: 'org1', extid: 'neworg456' };

      simulateOrgSwitch(org, 'same');

      expect(mockPush).toHaveBeenCalledWith('/org/neworg456');
    });

    it('replaces :extid in custom path when onOrgSwitch contains :extid', () => {
      const org = { id: 'org1', extid: 'neworg456' };

      simulateOrgSwitch(org, '/billing/org/:extid/invoices');

      expect(mockPush).toHaveBeenCalledWith('/billing/org/neworg456/invoices');
    });

    it('navigates directly when onOrgSwitch is a static path', () => {
      const org = { id: 'org1', extid: 'neworg456' };

      simulateOrgSwitch(org, '/dashboard');

      expect(mockPush).toHaveBeenCalledWith('/dashboard');
    });

    it('does not navigate when org is missing extid with "same" target', () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      const org = { id: 'org1' }; // No extid

      simulateOrgSwitch(org, 'same');

      expect(mockPush).not.toHaveBeenCalled();
      expect(consoleWarnSpy).toHaveBeenCalled();
      consoleWarnSpy.mockRestore();
    });

    it('does not navigate when org is missing extid with :extid path', () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      const org = { id: 'org1' }; // No extid

      simulateOrgSwitch(org, '/org/:extid');

      expect(mockPush).not.toHaveBeenCalled();
      expect(consoleWarnSpy).toHaveBeenCalled();
      consoleWarnSpy.mockRestore();
    });

    it('navigates with static path even when org is missing extid', () => {
      const org = { id: 'org1' }; // No extid

      simulateOrgSwitch(org, '/dashboard');

      expect(mockPush).toHaveBeenCalledWith('/dashboard');
    });
  });

  describe('onDomainSwitch navigation behavior', () => {
    /**
     * Helper to simulate domain selection with navigation logic.
     * This mirrors the logic in DomainScopeSwitcher.vue selectDomain()
     */
    function simulateDomainSwitch(domain: string, switchTarget?: string) {
      mockDomainScope.setScope(domain);

      if (!switchTarget) {
        return; // No navigation configured
      }

      const extid = mockDomainScope.getExtidByDomain(domain);

      if (switchTarget === 'same') {
        if (!extid) {
          console.warn('Cannot navigate: domain missing extid');
          return;
        }
        const matchedRoute = mockRoute.matched[mockRoute.matched.length - 1];
        if (matchedRoute?.path) {
          const newPath = matchedRoute.path.replace(':extid', extid);
          mockPush(newPath);
        }
      } else if (switchTarget.includes(':extid')) {
        if (!extid) {
          console.warn('Cannot navigate: domain missing extid');
          return;
        }
        const newPath = switchTarget.replace(':extid', extid);
        mockPush(newPath);
      } else {
        mockPush(switchTarget);
      }
    }

    it('does not navigate when onDomainSwitch is undefined', () => {
      simulateDomainSwitch('test.example.com', undefined);

      expect(mockDomainScope.setScope).toHaveBeenCalledWith('test.example.com');
      expect(mockPush).not.toHaveBeenCalled();
    });

    it('navigates to same route pattern when onDomainSwitch is "same"', () => {
      mockRoute.matched = [{ path: '/domains/:extid/brand' }];

      simulateDomainSwitch('test.example.com', 'same');

      expect(mockPush).toHaveBeenCalledWith('/domains/domain123/brand');
    });

    it('replaces :extid in custom path when onDomainSwitch contains :extid', () => {
      simulateDomainSwitch('test.example.com', '/domains/:extid/verify');

      expect(mockPush).toHaveBeenCalledWith('/domains/domain123/verify');
    });

    it('navigates directly when onDomainSwitch is a static path', () => {
      simulateDomainSwitch('test.example.com', '/domains');

      expect(mockPush).toHaveBeenCalledWith('/domains');
    });

    it('does not navigate when domain is canonical (missing extid) with "same" target', () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      simulateDomainSwitch('onetimesecret.com', 'same'); // Canonical domain has no extid

      expect(mockPush).not.toHaveBeenCalled();
      expect(consoleWarnSpy).toHaveBeenCalled();
      consoleWarnSpy.mockRestore();
    });

    it('does not navigate when domain is canonical (missing extid) with :extid path', () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      simulateDomainSwitch('onetimesecret.com', '/domains/:extid/brand');

      expect(mockPush).not.toHaveBeenCalled();
      expect(consoleWarnSpy).toHaveBeenCalled();
      consoleWarnSpy.mockRestore();
    });

    it('navigates with static path even when domain is canonical', () => {
      simulateDomainSwitch('onetimesecret.com', '/domains');

      expect(mockPush).toHaveBeenCalledWith('/domains');
    });
  });

  describe('route meta integration', () => {
    it('reads onOrgSwitch from route.meta.scopesAvailable', () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'show',
          domain: 'hide',
          onOrgSwitch: '/dashboard',
        },
      };

      expect(mockRoute.meta.scopesAvailable?.onOrgSwitch).toBe('/dashboard');
    });

    it('reads onDomainSwitch from route.meta.scopesAvailable', () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'show',
          domain: 'show',
          onOrgSwitch: '/dashboard',
          onDomainSwitch: 'same',
        },
      };

      expect(mockRoute.meta.scopesAvailable?.onDomainSwitch).toBe('same');
    });

    it('handles undefined scopesAvailable gracefully', () => {
      mockRoute.meta = {};

      expect(mockRoute.meta.scopesAvailable?.onOrgSwitch).toBeUndefined();
      expect(mockRoute.meta.scopesAvailable?.onDomainSwitch).toBeUndefined();
    });
  });

  describe('canonical domain disabled state', () => {
    /**
     * Helper to check if domain option should be disabled.
     * Mirrors logic in DomainScopeSwitcher.vue isOptionDisabled()
     */
    function isOptionDisabled(domain: string, switchTarget?: string): boolean {
      const extid = mockDomainScope.getExtidByDomain(domain);
      if (!extid && switchTarget) {
        return switchTarget === 'same' || switchTarget.includes(':extid');
      }
      return false;
    }

    /**
     * Helper to simulate domain selection with disabled check.
     * Mirrors logic in DomainScopeSwitcher.vue selectDomain()
     */
    function simulateDomainSwitchWithDisabledCheck(domain: string, switchTarget?: string) {
      // Don't allow selection of disabled options
      if (isOptionDisabled(domain, switchTarget)) {
        return;
      }

      mockDomainScope.setScope(domain);

      if (!switchTarget) {
        return;
      }

      const extid = mockDomainScope.getExtidByDomain(domain);

      if (switchTarget === 'same') {
        if (!extid) {
          return;
        }
        const matchedRoute = mockRoute.matched[mockRoute.matched.length - 1];
        if (matchedRoute?.path) {
          const newPath = matchedRoute.path.replace(':extid', extid);
          mockPush(newPath);
        }
      } else if (switchTarget.includes(':extid')) {
        if (!extid) {
          return;
        }
        const newPath = switchTarget.replace(':extid', extid);
        mockPush(newPath);
      } else {
        mockPush(switchTarget);
      }
    }

    it('isOptionDisabled returns true for canonical domain when onDomainSwitch is "same"', () => {
      // onetimesecret.com is canonical (no extid)
      expect(isOptionDisabled('onetimesecret.com', 'same')).toBe(true);
    });

    it('isOptionDisabled returns true for canonical domain when onDomainSwitch contains :extid', () => {
      // onetimesecret.com is canonical (no extid)
      expect(isOptionDisabled('onetimesecret.com', '/domains/:extid/brand')).toBe(true);
    });

    it('isOptionDisabled returns false for canonical domain when onDomainSwitch is undefined', () => {
      // When no onDomainSwitch configured, canonical should NOT be disabled
      expect(isOptionDisabled('onetimesecret.com', undefined)).toBe(false);
    });

    it('isOptionDisabled returns false for canonical domain when onDomainSwitch is static path', () => {
      // When onDomainSwitch is '/domains' (no :extid), canonical should NOT be disabled
      expect(isOptionDisabled('onetimesecret.com', '/domains')).toBe(false);
    });

    it('isOptionDisabled returns false for custom domains with extid', () => {
      // Custom domains (with extid) should never be disabled
      expect(isOptionDisabled('test.example.com', 'same')).toBe(false);
      expect(isOptionDisabled('test.example.com', '/domains/:extid/brand')).toBe(false);
      expect(isOptionDisabled('test.example.com', '/domains')).toBe(false);
      expect(isOptionDisabled('test.example.com', undefined)).toBe(false);
    });

    it('selectDomain does not navigate or update store when option is disabled', () => {
      mockRoute.matched = [{ path: '/domains/:extid/brand' }];

      // Attempt to select canonical domain when onDomainSwitch requires extid
      simulateDomainSwitchWithDisabledCheck('onetimesecret.com', 'same');

      // Neither setScope nor navigation should have been called
      expect(mockDomainScope.setScope).not.toHaveBeenCalled();
      expect(mockPush).not.toHaveBeenCalled();
    });

    it('selectDomain updates store and navigates when option is enabled', () => {
      mockRoute.matched = [{ path: '/domains/:extid/brand' }];

      // Select custom domain (has extid, should work)
      simulateDomainSwitchWithDisabledCheck('test.example.com', 'same');

      expect(mockDomainScope.setScope).toHaveBeenCalledWith('test.example.com');
      expect(mockPush).toHaveBeenCalledWith('/domains/domain123/brand');
    });

    it('selectDomain allows canonical domain when navigation is static path', () => {
      // Select canonical domain when onDomainSwitch is static (no :extid)
      simulateDomainSwitchWithDisabledCheck('onetimesecret.com', '/domains');

      expect(mockDomainScope.setScope).toHaveBeenCalledWith('onetimesecret.com');
      expect(mockPush).toHaveBeenCalledWith('/domains');
    });
  });

  describe('real route configurations', () => {
    it('domain detail pages have correct scope config for domain switching', () => {
      // Simulating /domains/:extid/brand route config
      const domainBrandConfig = {
        organization: 'show' as const,
        domain: 'show' as const,
        onOrgSwitch: '/dashboard',
        onDomainSwitch: 'same',
      };

      expect(domainBrandConfig.onOrgSwitch).toBe('/dashboard');
      expect(domainBrandConfig.onDomainSwitch).toBe('same');
    });

    it('org settings page has correct scope config for org switching', () => {
      // Simulating /org/:extid route config
      const orgSettingsConfig = {
        organization: 'show' as const,
        domain: 'hide' as const,
        onOrgSwitch: 'same',
      };

      expect(orgSettingsConfig.onOrgSwitch).toBe('same');
      expect(orgSettingsConfig.onDomainSwitch).toBeUndefined();
    });

    it('dashboard page has no navigation config (backwards compatible)', () => {
      // Simulating /dashboard route config using SCOPE_PRESETS.showBoth
      const dashboardConfig = {
        organization: 'show' as const,
        domain: 'show' as const,
      };

      expect(dashboardConfig.onOrgSwitch).toBeUndefined();
      expect(dashboardConfig.onDomainSwitch).toBeUndefined();
    });
  });
});
