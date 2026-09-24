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
    canonical_domain?: string;
    display_domain?: string;
    custom_domains?: string[];
    /**
     * Operator link pool (LINK_DOMAINS, #4063), already resolved server-side.
     *
     * Defaults to `[]`, which is NOT "empty pool" -- it is the wire shape of a
     * stale pre-#4063 server, and the composable maps it back to
     * [canonicalDomain]. That default is why every case written before #4063
     * keeps its exact HEAD behavior, and it is what makes those cases the AC1
     * regression fence.
     */
    link_domains?: string[];
    domain_strategy?: 'canonical' | 'subdomain' | 'custom' | 'invalid';
    /** Server-side preferred domain (sess['domain_context']). Schema default is null. */
    domain_context?: string | null;
  }) {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    setActivePinia(pinia);

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.domains_enabled = config.domains_enabled ?? true;
    bootstrapStore.site_host = config.site_host ?? 'onetimesecret.com';
    // Schema default is '' (older payloads omit it) - only set when provided
    bootstrapStore.canonical_domain = config.canonical_domain ?? '';
    bootstrapStore.display_domain = config.display_domain ?? config.site_host ?? 'onetimesecret.com';
    bootstrapStore.custom_domains = config.custom_domains ?? [];
    // Schema default is [] (pre-#4063 payloads omit it) - see the knob doc above
    bootstrapStore.link_domains = config.link_domains ?? [];
    bootstrapStore.domain_strategy = config.domain_strategy ?? 'canonical';
    bootstrapStore.domain_context = config.domain_context ?? null;

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

  describe('canonical link domain source', () => {
    // The canonical entry represents the share-LINK domain (DEFAULT_DOMAIN,
    // resolved server-side as default||site.host and exposed as
    // canonical_domain), not the app's own hostname (site_host).

    it('uses canonical_domain for the default entry when it differs from site_host', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.displayName).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expect(availableDomains.value).toContain('onetimesecret.com');
      expect(availableDomains.value).not.toContain('eu.onetimesecret.com');
    });

    it('falls back to site_host when canonical_domain is absent (older payloads)', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: '',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    // Split deployment: the browser is on a regional host (display_domain ===
    // site_host) while the canonical link domain differs. Being on a
    // canonical-set host is not "on a custom domain" -- the canonical entry
    // must still be listed so currentContext resolves to a selectable value.

    it('lists the canonical entry when browsing on a regional host with no custom domains', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'eu.onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, hasMultipleContexts } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['onetimesecret.com']);
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expect(availableDomains.value).toContain(currentContext.value.domain);
      expect(hasMultipleContexts.value).toBe(false);
    });

    it('lists canonical alongside custom domains when browsing on a regional host', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'eu.onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['acme.example.com', 'onetimesecret.com']);
      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(availableDomains.value).toContain(currentContext.value.domain);
    });

    it('setContext(canonical) round-trips when browsing on a regional host', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'eu.onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('acme.example.com');

      await setContext('onetimesecret.com');
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);

      await setContext('acme.example.com');
      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('marks custom domains non-canonical against canonical_domain, not site_host', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      // Custom domain preferred on init
      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);

      await setContext('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });
  });

  /**
   * Operator link pool (LINK_DOMAINS, #4063).
   *
   * The operator publishes the set of domains the picker may offer. That set is
   * NOT required to contain the canonical host: the motivating install serves
   * the app from an internal platform address (ge-abcd123.eu.otshosted.com)
   * which keeps working as a host but must never be offered as a link domain.
   * So `canonicalDomain` stops being a guaranteed-selectable value, and every
   * "fall back to canonical" site has to fall back to the pool instead.
   *
   * Two invariants drive these cases:
   *  - setContext silently drops any domain absent from availableDomains, so
   *    every path that produces a domain must produce a member of it, or ''
   *    (AC8). `expectSelectable` below is that check.
   *  - `link_domains: []` on the wire means exactly "stale pre-#4063 server",
   *    never "empty pool" -- the server resolves an unset LINK_DOMAINS to
   *    [canonical_domain] before it ever reaches the browser.
   *
   * Trap worth knowing when reading these: `isCanonical` is still
   * `domain === canonicalDomain`. With the canonical host excluded from the
   * pool, EVERY selectable domain reports isCanonical === false. "Has no extid"
   * and "is the canonical domain" were the same thing before #4063 and are not
   * any more.
   */
  describe('operator link pool (#4063)', () => {
    /** The install's own host: serves the app, deliberately not offered. */
    const INTERNAL_HOST = 'ge-abcd123.eu.otshosted.com';

    /**
     * AC8: currentContext.domain must always be something setContext would
     * accept -- a member of availableDomains -- or the empty string.
     * Compared as an object so a failure names the offending domain.
     */
    const expectSelectable = (available: string[], domain: string) =>
      expect({ domain, selectable: domain === '' || available.includes(domain) }).toEqual({
        domain,
        selectable: true,
      });

    it('AC1: a stale pre-#4063 payload (link_domains: []) lists customs then canonical', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'eu.onetimesecret.com',
        link_domains: [],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      // Byte-identical to HEAD: the composable re-derives [canonicalDomain]
      // only because the payload carried no pool at all.
      expect(availableDomains.value).toEqual([
        'acme.example.com',
        'widgets.example.com',
        'onetimesecret.com',
      ]);
      expect(currentContext.value.domain).toBe('acme.example.com');
      expectSelectable(availableDomains.value, currentContext.value.domain);
    });

    it('AC1: an unset LINK_DOMAINS (pool === [canonical]) lists customs then canonical', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'eu.onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'eu.onetimesecret.com',
        // What a #4063 server actually sends when LINK_DOMAINS is unset.
        link_domains: ['onetimesecret.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual([
        'acme.example.com',
        'widgets.example.com',
        'onetimesecret.com',
      ]);
      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.isCanonical).toBe(false);
    });

    it('AC2: a pool that excludes the canonical host keeps it out of the picker', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        link_domains: ['short.example.com'],
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, setContext } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['short.example.com']);
      expect(availableDomains.value).not.toContain(INTERNAL_HOST);
      expect(currentContext.value.domain).toBe('short.example.com');
      expect(currentContext.value.displayName).toBe('short.example.com');
      // The excluded canonical host is not selectable, so nothing can be the
      // "canonical" row: isCanonical is false for every offered domain.
      expect(currentContext.value.isCanonical).toBe(false);
      expectSelectable(availableDomains.value, currentContext.value.domain);

      // Not merely hidden: setContext rejects it like any unknown domain.
      await setContext(INTERNAL_HOST);
      expect(currentContext.value.domain).toBe('short.example.com');
    });

    it('AC8: resetContext lands on a pool member when the canonical host is excluded', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        custom_domains: ['acme.example.com'],
        link_domains: ['short.example.com', 'links.example.net'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, setContext, resetContext } = useDomainContext();

      await waitForInit();

      await setContext('links.example.net');
      expect(currentContext.value.domain).toBe('links.example.net');

      await resetContext();

      // Pool head, not the hidden canonical host.
      expect(currentContext.value.domain).toBe('short.example.com');
      expect(currentContext.value.domain).not.toBe(INTERNAL_HOST);
      expectSelectable(availableDomains.value, currentContext.value.domain);
    });

    it('AC8: currentContext falls back to a pool member when no organization is set', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        link_domains: ['short.example.com'],
      });

      // Anonymous / pre-org boot: the fetcher short-circuits and returns false,
      // so initialization never assigns currentDomain and currentContext is
      // resolved entirely by its own fallback.
      mockOrganizationStoreState.currentOrganization = null;
      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(currentContext.value.domain).toBe('short.example.com');
      expect(currentContext.value.domain).not.toBe(INTERNAL_HOST);
      expectSelectable(availableDomains.value, currentContext.value.domain);
    });

    it('AC8: currentContext falls back to a pool member when fetchAllPermissions rejects', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        link_domains: ['short.example.com'],
      });

      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      mockFetchAllPermissions.mockRejectedValue(new Error('Network error'));

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, isLoadingDomains } = useDomainContext();

      await waitForInit();

      expect(isLoadingDomains.value).toBe(false);
      expect(currentContext.value.domain).toBe('short.example.com');
      expect(currentContext.value.domain).not.toBe(INTERNAL_HOST);
      expectSelectable(availableDomains.value, currentContext.value.domain);

      warnSpy.mockRestore();
    });

    it('AC8: the domains-disabled branch lands on a pool member', async () => {
      setupBootstrapStore({
        domains_enabled: false,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        link_domains: ['short.example.com'],
      });

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, isContextActive } = useDomainContext();

      await waitForInit();

      expect(isContextActive.value).toBe(false);
      expect(currentContext.value.domain).toBe('short.example.com');
      expectSelectable(availableDomains.value, currentContext.value.domain);
    });

    it('resets to the canonical host when it IS a pool member', async () => {
      // The historical contract (see 'resetContext > resets to canonical
      // domain'): reset means "back to the default link domain". Substituting
      // getPreferredDomain here would return the first CUSTOM domain instead.
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        custom_domains: ['acme.example.com'],
        link_domains: ['short.example.com', 'onetimesecret.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, setContext, resetContext } = useDomainContext();

      await waitForInit();

      await setContext('acme.example.com');
      expect(currentContext.value.domain).toBe('acme.example.com');

      await resetContext();

      // Canonical wins over the pool head because it is a member.
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
      expectSelectable(availableDomains.value, currentContext.value.domain);
    });

    it('prefers a real custom domain over an operator pool entry', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        custom_domains: ['acme.example.com'],
        link_domains: ['go.acme.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['acme.example.com', 'go.acme.com']);
      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(currentContext.value.extid).toBe('cd_acme_example_com');
    });

    it('prefers a registered custom domain that is ALSO a pool entry', async () => {
      // Overlap case: ConfigureDomains warns but does not prevent an operator
      // from listing a host that is a registered CustomDomain, so both sets can
      // name the same host. getPreferredDomain's predicate ("not a pool entry")
      // then matches nothing and the tail takes over -- which is still correct,
      // because buildAvailableDomains puts the org's own domains ahead of every
      // pool entry, so `available[0]` IS the customer's domain. The pool entry
      // cannot win here regardless of the pool's own order.
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        custom_domains: ['brand.example.com'],
        link_domains: ['go.example.com', 'brand.example.com'],
      });

      setMockDomains('org-ext-test-123', ['brand.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['brand.example.com', 'go.example.com']);
      expect(currentContext.value.domain).toBe('brand.example.com');
      expect(currentContext.value.extid).toBe('cd_brand_example_com');
    });

    it('prefers the canonical entry over a sibling pool entry when no custom domains exist', async () => {
      // The discriminating case for "is this a real custom domain?": the old
      // test was `d !== canonicalDomain`, which picks the SECOND pool entry
      // here because it merely differs from canonical. Pool membership is the
      // correct test, and it leaves the canonical entry preferred.
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        link_domains: ['onetimesecret.com', 'short.example.com'],
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['onetimesecret.com', 'short.example.com']);
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    it('multi-entry pool: setContext round-trips to any member', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        link_domains: ['a.example.com', 'b.example.com', 'c.example.com'],
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, hasMultipleContexts, setContext } =
        useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual([
        'a.example.com',
        'b.example.com',
        'c.example.com',
      ]);
      expect(hasMultipleContexts.value).toBe(true);
      expect(currentContext.value.domain).toBe('a.example.com');

      await setContext('c.example.com');
      expect(currentContext.value.domain).toBe('c.example.com');
      expect(currentContext.value.extid).toBeUndefined();

      await setContext('b.example.com');
      expect(currentContext.value.domain).toBe('b.example.com');
      expectSelectable(availableDomains.value, currentContext.value.domain);
    });

    it('a pool entry that is also a registered custom domain appears once and keeps its extid', async () => {
      // The operator listed a host a customer has also registered. It must not
      // appear twice, and the surviving row is the CUSTOM one -- dropping the
      // extid would cost it its settings gear and its :extid navigation.
      setupBootstrapStore({
        domains_enabled: true,
        site_host: INTERNAL_HOST,
        canonical_domain: INTERNAL_HOST,
        display_domain: INTERNAL_HOST,
        custom_domains: ['acme.example.com'],
        link_domains: ['acme.example.com', 'short.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains, getExtidByDomain, setContext } =
        useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['acme.example.com', 'short.example.com']);
      expect(
        availableDomains.value.filter((d) => d === 'acme.example.com')
      ).toHaveLength(1);
      expect(getExtidByDomain('acme.example.com')).toBe('cd_acme_example_com');

      await setContext('acme.example.com');
      expect(currentContext.value.extid).toBe('cd_acme_example_com');
    });

    // ------------------------------------------------------------------------
    // Branded host: the canonical domain is not offerable
    //
    // Selecting it there is ignored end to end -- process_share_domain nils
    // anchor hosts, then determine_share_domain falls through to
    // `display_domain if custom_domain?` and anchors the link on the branded
    // host regardless. Offering a row the generated link contradicts is worse
    // than not offering it. Pool members are a different question: v2 honors
    // an authenticated user's explicit pool selection from a branded host, so
    // they stay.
    // ------------------------------------------------------------------------
    it('drops the canonical domain from the picker while browsing a branded host', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'acme.example.com',
        domain_strategy: 'custom',
        custom_domains: ['acme.example.com'],
        link_domains: ['onetimesecret.com', 'short.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains, setContext, currentContext } = useDomainContext();

      await waitForInit();

      // Canonical gone; the pool member survives.
      expect(availableDomains.value).toEqual(['acme.example.com', 'short.example.com']);
      expect(availableDomains.value).not.toContain('onetimesecret.com');

      // And it is genuinely unselectable, not merely hidden.
      await setContext('onetimesecret.com');
      expect(currentContext.value.domain).not.toBe('onetimesecret.com');
    });

    it('keeps the canonical domain offerable on a link-pool host', async () => {
      // Discriminates the guard from the `displayDomain !== canonicalDomain`
      // heuristic it replaced: on a pool host those two also differ, but the
      // strategy is :canonical and none of the branded-host rules apply.
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'short.example.com',
        domain_strategy: 'canonical',
        link_domains: ['onetimesecret.com', 'short.example.com'],
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['onetimesecret.com', 'short.example.com']);
    });

    // ------------------------------------------------------------------------
    // Host normalization
    //
    // link_domains comes out of the server's PARSED canonical set (lowercased,
    // port-stripped) while canonical_domain / site_host are the configured
    // strings verbatim -- and site.host legally carries a port. Comparing the
    // two families raw made `linkDomains.includes(canonicalDomain)` fail on
    // every port-bearing canonical host, which is the single test deciding
    // whether canonical counts as a pool member at all.
    // ------------------------------------------------------------------------
    it('treats a port-bearing canonical host as the pool member it is', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com:3000',
        canonical_domain: 'onetimesecret.com:3000',
        display_domain: 'onetimesecret.com:3000',
        link_domains: ['onetimesecret.com', 'short.example.com'],
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, availableDomains } = useDomainContext();

      await waitForInit();

      expect(availableDomains.value).toEqual(['onetimesecret.com', 'short.example.com']);
      // Canonical is preferred (it IS a member) and reports itself as such.
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    it('accepts a raw host in setContext and normalizes it', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        link_domains: ['onetimesecret.com', 'short.example.com'],
      });

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { currentContext, setContext } = useDomainContext();

      await waitForInit();

      await setContext('Short.Example.COM:8443');
      expect(currentContext.value.domain).toBe('short.example.com');
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
      await setContext('acme.example.com');
      expect(currentContext.value.domain).toBe('acme.example.com');

      // Reset
      await resetContext();
      expect(currentContext.value.domain).toBe('onetimesecret.com');
      expect(currentContext.value.isCanonical).toBe(true);
    });

    // The reset writes the default through BOTH halves of the preference
    // rather than clearing the local half. `sess['domain_context']` has no
    // clear endpoint, so a local-only reset left the server still naming the
    // old selection and selectBestDomain restored it on the next load.
    it('replaces domainContext in sessionStorage with the default domain', async () => {
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

      await setContext('acme.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');

      await resetContext();
      expect(mockSessionStorage.getItem('domainContext')).toBe('onetimesecret.com');
    });

    it('falls back to the served host when there is no offerable pool', async () => {
      // On a branded host with no LINK_DOMAINS configured the pool is
      // canonical-only and canonical is dropped, so the pool fallback is ''.
      // Resetting to '' would be a half-reset: the endpoint rejects a blank
      // domain, so sess['domain_context'] would keep the old selection and
      // selectBestDomain would restore it. The served host is the value both
      // halves accept, and the one links anchor on from here regardless.
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'acme.example.com',
        domain_strategy: 'custom',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { setContext, resetContext } = useDomainContext();

      await waitForInit();

      await setContext('acme.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');

      await resetContext();
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');
    });

    it('clears domainContext when not on a branded host and nothing is offerable', async () => {
      // No pool and no branded host to fall back to: '' is the honest answer,
      // and clearing is the only coherent write (a blank domain cannot be
      // synced, so storing it would make the two halves disagree).
      setupBootstrapStore({
        domains_enabled: true,
        site_host: '',
        canonical_domain: '',
        display_domain: '',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await import('@/shared/composables/useDomainContext');
      const { setContext, resetContext } = useDomainContext();

      await waitForInit();

      await setContext('acme.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');

      await resetContext();
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

    // Selecting canonical persists like any other pool member. It used to be
    // carved out on the reasoning that "absent sessionStorage IS canonical",
    // which held only while nothing else remembered a selection --
    // `sess['domain_context']` does, outlives sessionStorage, and has no clear
    // endpoint. selectBestDomain reads the server half first, so the carve-out
    // made switching back to canonical revert on the next reload.
    it('selecting canonical domain syncs to the backend', async () => {
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

      expect(mockApiPost).toHaveBeenCalledWith(
        '/api/account/update-domain-context',
        { domain: 'onetimesecret.com' }
      );
    });

    it('selecting canonical domain overwrites a stale sessionStorage domainContext', async () => {
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

      expect(mockSessionStorage.getItem('domainContext')).toBe('onetimesecret.com');
    });

    // Regression, the bug the carve-out caused: a stale server-side
    // domain_context must not survive an explicit switch back to canonical.
    it('switching back to canonical survives a reload driven by the server context', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        display_domain: 'onetimesecret.com',
        domain_context: 'acme.example.com',
        custom_domains: ['acme.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { setContext, currentContext } = useDomainContext();

      await waitForInit();

      // The server preference wins on load...
      expect(currentContext.value.domain).toBe('acme.example.com');

      await setContext('onetimesecret.com');

      // ...and the switch back must be written through to the server, not just
      // dropped locally, or the next load restores 'acme.example.com'.
      expect(mockApiPost).toHaveBeenCalledWith(
        '/api/account/update-domain-context',
        { domain: 'onetimesecret.com' }
      );
      expect(mockSessionStorage.getItem('domainContext')).toBe('onetimesecret.com');
    });

    // The branded-host reset used to land on '' and take persistDomainContext's
    // clearing tail: sessionStorage was dropped while sess['domain_context']
    // kept naming the old selection, and selectBestDomain -- which reads the
    // server half FIRST -- restored it on the next load. This is the DEFAULT
    // configuration, not an edge case: getOfferableLinkDomains drops the
    // canonical entry on a branded host, and with LINK_DOMAINS unset that is
    // the entire pool. '' cannot be synced (the endpoint rejects a blank
    // domain), so the reset lands on the served host instead -- which is where
    // determine_share_domain anchors links from here anyway.
    it('resetContext on a branded host writes the served host through both halves', async () => {
      setupBootstrapStore({
        domains_enabled: true,
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        display_domain: 'acme.example.com',
        domain_strategy: 'custom',
        custom_domains: ['acme.example.com', 'widgets.example.com'],
      });

      setMockDomains('org-ext-test-123', ['acme.example.com', 'widgets.example.com']);

      const { useDomainContext } = await importWithMockApi();
      const { currentContext, setContext, resetContext } = useDomainContext();

      await waitForInit();

      await setContext('widgets.example.com');
      expect(currentContext.value.domain).toBe('widgets.example.com');
      mockApiPost.mockClear();

      await resetContext();

      expect(currentContext.value.domain).toBe('acme.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('acme.example.com');
      // The half that used to be left stale.
      expect(mockApiPost).toHaveBeenCalledWith(
        '/api/account/update-domain-context',
        { domain: 'acme.example.com' }
      );
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

    // #4063: an operator link-pool entry has no CustomDomain row, so it is
    // never in custom_domains. Persistence is gated on custom_domains ∪
    // link_domains; without the union the selection was dropped on both sides
    // and the picker reset on every reload. The server admits it via
    // DomainStrategy.canonical_host? (update_domain_context.rb:97).
    it('selecting an operator link-pool domain stores it and triggers POST', async () => {
      const { bootstrapStore } = setupBootstrapStore({
        domains_enabled: true,
        site_host: 'ge-abcd123.eu.otshosted.com',
        canonical_domain: 'ge-abcd123.eu.otshosted.com',
        display_domain: 'ge-abcd123.eu.otshosted.com',
      });
      bootstrapStore.link_domains = ['a.example.com', 'b.example.com'];

      setMockDomains('org-ext-test-123', []);

      const { useDomainContext } = await importWithMockApi();
      const { setContext, currentContext } = useDomainContext();

      await waitForInit();

      mockApiPost.mockClear();

      await setContext('b.example.com');

      expect(currentContext.value.domain).toBe('b.example.com');
      expect(mockSessionStorage.getItem('domainContext')).toBe('b.example.com');
      expect(mockApiPost).toHaveBeenCalledWith('/api/account/update-domain-context', {
        domain: 'b.example.com',
      });

      // A sibling of a pool member is not a member: the server would reject it,
      // so nothing is persisted (setContext also rejects it as unavailable).
      mockApiPost.mockClear();
      await setContext('c.example.com');

      expect(mockApiPost).not.toHaveBeenCalled();
      expect(mockSessionStorage.getItem('domainContext')).toBe('b.example.com');
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
