// src/tests/composables/useEntitlements.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref, nextTick } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { organizationSchema } from '@/schemas/shapes/organizations/organization';
import type { Organization } from '@/types/organization';
import {
  createMockOrganization as createMockOrganizationWire,
  mockOrganizations,
  type OrganizationWire,
} from '../fixtures/billing.fixture';

const { mockGet } = vi.hoisted(() => ({
  mockGet: vi.fn(),
}));

vi.mock('@/api', () => ({ createApi: () => ({ get: mockGet }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: (key: string) => `translated:${key}` }) }));

// useEntitlements takes the parsed `Organization` shape (Date timestamps),
// but the billing fixtures return wire format (epoch-second numbers) meant
// for mocking API responses. Parse through the production schema so tests
// feed the composable the same shape the real store produces.
const mockOrg = (overrides: Partial<OrganizationWire> = {}): Organization =>
  organizationSchema.parse(createMockOrganizationWire(overrides));

const freeOrg = organizationSchema.parse(mockOrganizations.free);

describe('useEntitlements', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockReset();
  });

  afterEach(() => {
    vi.resetModules();
  });

  /**
   * Helper to set up bootstrapStore with billing configuration
   */
  function setupBootstrapStore(config: { billing_enabled?: boolean } = {}) {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    setActivePinia(pinia);

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.billing_enabled = config.billing_enabled ?? true;

    return { pinia, bootstrapStore };
  }

  async function importFresh() {
    vi.resetModules();
    setupBootstrapStore({ billing_enabled: true });
    const { useEntitlements } = await import('@/shared/composables/useEntitlements');
    return useEntitlements;
  }

  const mockApiResponse = {
    data: {
      entitlements: [
        { key: 'api_access', display_name: 'web.billing.entitlements.api_access', category: 'infrastructure' },
        { key: 'custom_domains', display_name: 'web.billing.entitlements.custom_domains', category: 'infrastructure' },
      ],
      plans: [{ plan_id: 'identity_plus_v1', name: 'Identity Plus', entitlements: ['api_access', 'custom_domains'] }],
    },
  };

  describe('initDefinitions', () => {
    it('loads entitlement definitions from API', async () => {
      mockGet.mockResolvedValueOnce(mockApiResponse);
      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(mockOrg());
      const { initDefinitions, hasDefinitions, isLoadingDefinitions } = useEntitlements(org);

      expect(hasDefinitions.value).toBe(false);
      await initDefinitions();
      await nextTick();

      expect(mockGet).toHaveBeenCalledWith('/api/account/entitlements');
      expect(hasDefinitions.value).toBe(true);
      expect(isLoadingDefinitions.value).toBe(false);
    });

    it('sets isLoadingDefinitions during API call', async () => {
      let resolveApi: (value: unknown) => void;
      mockGet.mockReturnValueOnce(new Promise((resolve) => { resolveApi = resolve; }));

      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(mockOrg());
      const { initDefinitions, isLoadingDefinitions } = useEntitlements(org);

      const initPromise = initDefinitions();
      await nextTick();
      expect(isLoadingDefinitions.value).toBe(true);

      resolveApi!({ data: { entitlements: [], plans: [] } });
      await initPromise;
      await nextTick();
      expect(isLoadingDefinitions.value).toBe(false);
    });

    it('does not fetch again if already initialized', async () => {
      mockGet.mockResolvedValue({ data: { entitlements: [], plans: [] } });
      const useEntitlements = await importFresh();
      const { initDefinitions } = useEntitlements(ref(mockOrg()));

      await initDefinitions();
      await initDefinitions();
      expect(mockGet).toHaveBeenCalledTimes(1);
    });
  });

  describe('formatEntitlement', () => {
    it('returns translated i18n key from store when available', async () => {
      mockGet.mockResolvedValueOnce(mockApiResponse);
      const useEntitlements = await importFresh();
      const { initDefinitions, formatEntitlement } = useEntitlements(ref(mockOrg()));

      await initDefinitions();
      await nextTick();
      expect(formatEntitlement('api_access')).toBe('translated:web.billing.entitlements.api_access');
    });

    it('falls back to hardcoded i18n keys when store has no data', async () => {
      const useEntitlements = await importFresh();
      const { formatEntitlement } = useEntitlements(ref(mockOrg()));
      expect(formatEntitlement('api_access')).toBe('translated:web.billing.overview.entitlements.api_access');
    });

    it('returns raw key when no mapping exists', async () => {
      const useEntitlements = await importFresh();
      const { formatEntitlement } = useEntitlements(ref(mockOrg()));
      expect(formatEntitlement('unknown_entitlement')).toBe('unknown_entitlement');
    });
  });

  describe('null organization handling', () => {
    it('handles null organization gracefully', async () => {
      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(null);
      const { can, limit, entitlements, planId } = useEntitlements(org);

      expect(can('api_access')).toBe(false);
      expect(limit('teams')).toBe(0);
      expect(entitlements.value).toEqual([]);
      expect(planId.value).toBeUndefined();
    });
  });

  describe('entitlements reactivity', () => {
    it('entitlements derived from organization reactively', async () => {
      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(freeOrg);
      const { entitlements, can, planId } = useEntitlements(org);

      expect(entitlements.value).toEqual([]);
      expect(can('api_access')).toBe(false);
      expect(planId.value).toBe('free_v1');

      org.value = mockOrg({ entitlements: ['api_access'], planid: 'team_plus_v1' });
      await nextTick();

      expect(entitlements.value).toContain('api_access');
      expect(can('api_access')).toBe(true);
      expect(planId.value).toBe('team_plus_v1');
    });
  });

  describe('definitionsError', () => {
    it('captures API failures', async () => {
      mockGet.mockRejectedValueOnce(new Error('Network error'));
      const useEntitlements = await importFresh();
      const { initDefinitions, definitionsError } = useEntitlements(ref(mockOrg()));

      await initDefinitions();
      await nextTick();
      expect(definitionsError.value).toBe('Network error');
    });

    it('error is null on successful load', async () => {
      mockGet.mockResolvedValueOnce({ data: { entitlements: [], plans: [] } });
      const useEntitlements = await importFresh();
      const { initDefinitions, definitionsError } = useEntitlements(ref(mockOrg()));

      await initDefinitions();
      await nextTick();
      expect(definitionsError.value).toBeNull();
    });

    it('falls back gracefully when API fails', async () => {
      mockGet.mockRejectedValueOnce(new Error('API unavailable'));
      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(mockOrg({ entitlements: ['api_access'] }));
      const { initDefinitions, can, formatEntitlement } = useEntitlements(org);

      await initDefinitions();
      await nextTick();
      expect(can('api_access')).toBe(true);
      expect(formatEntitlement('api_access')).toBe('translated:web.billing.overview.entitlements.api_access');
    });
  });

  describe('standalone mode', () => {
    it('grants all entitlements when billing is disabled', async () => {
      vi.resetModules();
      setupBootstrapStore({ billing_enabled: false });
      const { useEntitlements } = await import('@/shared/composables/useEntitlements');
      const { can, isStandaloneMode } = useEntitlements(ref(freeOrg));

      expect(isStandaloneMode.value).toBe(true);
      expect(can('api_access')).toBe(true);
      expect(can('any_entitlement')).toBe(true);
    });

    it('respects org entitlements when billing is enabled', async () => {
      vi.resetModules();
      setupBootstrapStore({ billing_enabled: true });
      const { useEntitlements } = await import('@/shared/composables/useEntitlements');
      const { can, isStandaloneMode } = useEntitlements(ref(freeOrg));

      expect(isStandaloneMode.value).toBe(false);
      expect(can('api_access')).toBe(false);
    });
  });

  describe('upgradePath', () => {
    it('returns null when organization already has entitlement', async () => {
      const useEntitlements = await importFresh();
      const { upgradePath } = useEntitlements(ref(mockOrg({ entitlements: ['api_access'] })));
      expect(upgradePath('api_access')).toBeNull();
    });

    it('returns plan from API mapping when available', async () => {
      mockGet.mockResolvedValueOnce({
        data: {
          entitlements: [{ key: 'audit_logs', display_name: 'Audit Logs', category: 'security' }],
          plans: [{ plan_id: 'team_plus_v1', name: 'Team Plus', entitlements: ['audit_logs'] }],
        },
      });
      const useEntitlements = await importFresh();
      const org = ref(mockOrg({ entitlements: [] }));
      const { initDefinitions, upgradePath } = useEntitlements(org);

      await initDefinitions();
      await nextTick();
      expect(upgradePath('audit_logs')).toBe('team_plus_v1');
    });

    it('returns null when store not initialized (no fallback)', async () => {
      const useEntitlements = await importFresh();
      const { upgradePath } = useEntitlements(ref(mockOrg({ entitlements: [] })));
      // No fallback - callers must ensure initDefinitions() runs first
      expect(upgradePath('audit_logs')).toBeNull();
    });
  });

  describe('hasReachedLimit', () => {
    it('returns true when current equals or exceeds limit', async () => {
      const useEntitlements = await importFresh();
      const org = ref(mockOrg({ limits: { teams: 5 } }));
      const { hasReachedLimit } = useEntitlements(org);

      expect(hasReachedLimit('teams', 5)).toBe(true);
      expect(hasReachedLimit('teams', 6)).toBe(true);
    });

    it('returns false when current is below limit or limit is 0', async () => {
      const useEntitlements = await importFresh();
      const org = ref(mockOrg({ limits: { teams: 5 } }));
      const { hasReachedLimit } = useEntitlements(org);
      expect(hasReachedLimit('teams', 3)).toBe(false);

      const useEntitlements2 = await importFresh();
      const { hasReachedLimit: hasReachedLimit2 } = useEntitlements2(
        ref(mockOrg({ limits: { teams: 0 } }))
      );
      expect(hasReachedLimit2('teams', 100)).toBe(false);
    });
  });
});
