// src/tests/composables/useEntitlements.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref, nextTick } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import type { Organization } from '@/types/organization';
import { createMockOrganization, mockOrganizations } from '../fixtures/billing.fixture';

const { mockGet, mockWindowGet } = vi.hoisted(() => ({
  mockGet: vi.fn(),
  mockWindowGet: vi.fn(),
}));

vi.mock('@/api', () => ({ createApi: () => ({ get: mockGet }) }));
vi.mock('@/services/window.service', () => ({ WindowService: { get: mockWindowGet } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: (key: string) => `translated:${key}` }) }));

describe('useEntitlements', () => {
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockGet.mockReset();
    mockWindowGet.mockReturnValue(true);
  });

  afterEach(() => { vi.resetModules(); });

  async function importFresh() {
    vi.resetModules();
    pinia = createPinia();
    setActivePinia(pinia);
    const { useEntitlements } = await import('@/shared/composables/useEntitlements');
    return useEntitlements;
  }

  const mockApiResponse = {
    data: {
      entitlements: [
        { key: 'api_access', display_name: 'web.billing.entitlements.api_access', category: 'infrastructure' },
        { key: 'custom_domains', display_name: 'web.billing.entitlements.custom_domains', category: 'infrastructure' },
      ],
      plans: [{ plan_id: 'identity_v1', name: 'Identity Plus', entitlements: ['api_access', 'custom_domains'] }],
    },
  };

  describe('initDefinitions', () => {
    it('loads entitlement definitions from API', async () => {
      mockGet.mockResolvedValueOnce(mockApiResponse);
      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(createMockOrganization());
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
      const org = ref<Organization | null>(createMockOrganization());
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
      const { initDefinitions } = useEntitlements(ref(createMockOrganization()));

      await initDefinitions();
      await initDefinitions();
      expect(mockGet).toHaveBeenCalledTimes(1);
    });
  });

  describe('formatEntitlement', () => {
    it('returns translated i18n key from store when available', async () => {
      mockGet.mockResolvedValueOnce(mockApiResponse);
      const useEntitlements = await importFresh();
      const { initDefinitions, formatEntitlement } = useEntitlements(ref(createMockOrganization()));

      await initDefinitions();
      await nextTick();
      expect(formatEntitlement('api_access')).toBe('translated:web.billing.entitlements.api_access');
    });

    it('falls back to hardcoded i18n keys when store has no data', async () => {
      const useEntitlements = await importFresh();
      const { formatEntitlement } = useEntitlements(ref(createMockOrganization()));
      expect(formatEntitlement('api_access')).toBe('translated:web.billing.overview.entitlements.api_access');
    });

    it('returns raw key when no mapping exists', async () => {
      const useEntitlements = await importFresh();
      const { formatEntitlement } = useEntitlements(ref(createMockOrganization()));
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
      const org = ref<Organization | null>(mockOrganizations.free);
      const { entitlements, can, planId } = useEntitlements(org);

      expect(entitlements.value).toEqual([]);
      expect(can('api_access')).toBe(false);
      expect(planId.value).toBe('free_v1');

      org.value = createMockOrganization({ entitlements: ['api_access'], planid: 'team_plus_v1_monthly' });
      await nextTick();

      expect(entitlements.value).toContain('api_access');
      expect(can('api_access')).toBe(true);
      expect(planId.value).toBe('team_plus_v1_monthly');
    });
  });

  describe('definitionsError', () => {
    it('captures API failures', async () => {
      mockGet.mockRejectedValueOnce(new Error('Network error'));
      const useEntitlements = await importFresh();
      const { initDefinitions, definitionsError } = useEntitlements(ref(createMockOrganization()));

      await initDefinitions();
      await nextTick();
      expect(definitionsError.value).toBe('Network error');
    });

    it('error is null on successful load', async () => {
      mockGet.mockResolvedValueOnce({ data: { entitlements: [], plans: [] } });
      const useEntitlements = await importFresh();
      const { initDefinitions, definitionsError } = useEntitlements(ref(createMockOrganization()));

      await initDefinitions();
      await nextTick();
      expect(definitionsError.value).toBeNull();
    });

    it('falls back gracefully when API fails', async () => {
      mockGet.mockRejectedValueOnce(new Error('API unavailable'));
      const useEntitlements = await importFresh();
      const org = ref<Organization | null>(createMockOrganization({ entitlements: ['api_access'] }));
      const { initDefinitions, can, formatEntitlement } = useEntitlements(org);

      await initDefinitions();
      await nextTick();
      expect(can('api_access')).toBe(true);
      expect(formatEntitlement('api_access')).toBe('translated:web.billing.overview.entitlements.api_access');
    });
  });

  describe('standalone mode', () => {
    it('grants all entitlements when billing is disabled', async () => {
      mockWindowGet.mockReturnValue(false);
      const useEntitlements = await importFresh();
      const { can, isStandaloneMode } = useEntitlements(ref(mockOrganizations.free));

      expect(isStandaloneMode.value).toBe(true);
      expect(can('api_access')).toBe(true);
      expect(can('any_entitlement')).toBe(true);
    });

    it('respects org entitlements when billing is enabled', async () => {
      mockWindowGet.mockReturnValue(true);
      const useEntitlements = await importFresh();
      const { can, isStandaloneMode } = useEntitlements(ref(mockOrganizations.free));

      expect(isStandaloneMode.value).toBe(false);
      expect(can('api_access')).toBe(false);
    });
  });

  describe('upgradePath', () => {
    it('returns null when organization already has entitlement', async () => {
      const useEntitlements = await importFresh();
      const { upgradePath } = useEntitlements(ref(createMockOrganization({ entitlements: ['api_access'] })));
      expect(upgradePath('api_access')).toBeNull();
    });

    it('returns plan from API mapping when available', async () => {
      mockGet.mockResolvedValueOnce({
        data: {
          entitlements: [{ key: 'audit_logs', display_name: 'Audit Logs', category: 'security' }],
          plans: [{ plan_id: 'multi_team_v1', name: 'Team Plus', entitlements: ['audit_logs'] }],
        },
      });
      const useEntitlements = await importFresh();
      const org = ref(createMockOrganization({ entitlements: [] }));
      const { initDefinitions, upgradePath } = useEntitlements(org);

      await initDefinitions();
      await nextTick();
      expect(upgradePath('audit_logs')).toBe('multi_team_v1');
    });

    it('falls back to hardcoded mapping when store not initialized', async () => {
      const useEntitlements = await importFresh();
      const { upgradePath } = useEntitlements(ref(createMockOrganization({ entitlements: [] })));
      expect(upgradePath('audit_logs')).toBe('multi_team_v1');
    });
  });

  describe('hasReachedLimit', () => {
    it('returns true when current equals or exceeds limit', async () => {
      const useEntitlements = await importFresh();
      const org = ref(createMockOrganization({ limits: { teams: 5 } }));
      const { hasReachedLimit } = useEntitlements(org);

      expect(hasReachedLimit('teams', 5)).toBe(true);
      expect(hasReachedLimit('teams', 6)).toBe(true);
    });

    it('returns false when current is below limit or limit is 0', async () => {
      const useEntitlements = await importFresh();
      const org = ref(createMockOrganization({ limits: { teams: 5 } }));
      const { hasReachedLimit } = useEntitlements(org);
      expect(hasReachedLimit('teams', 3)).toBe(false);

      const useEntitlements2 = await importFresh();
      const { hasReachedLimit: hasReachedLimit2 } = useEntitlements2(
        ref(createMockOrganization({ limits: { teams: 0 } }))
      );
      expect(hasReachedLimit2('teams', 100)).toBe(false);
    });
  });
});
