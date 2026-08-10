// src/tests/apps/admin/useOrganizationsList.spec.ts

import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => mockApi,
}));

import { useOrganizationsList } from '@/apps/admin/composables/useOrganizationsList';
import type { ColonelOrganizationsCache } from '@/schemas/api/internal/responses/colonel';

/** A minimal row satisfying every required colonelOrganizationSchema field. */
function orgRow(orgId: string) {
  return {
    org_id: orgId,
    extid: `on_${orgId}`,
    display_name: orgId.toUpperCase(),
    contact_email: null,
    owner_id: null,
    owner_email: null,
    member_count: 1,
    domain_count: 0,
    is_default: false,
    created: 1700000000,
    updated: null,
    planid: null,
    stripe_customer_id: null,
    stripe_subscription_id: null,
    subscription_status: null,
    subscription_period_end: null,
    billing_email: null,
    sync_status: 'unknown',
    sync_status_reason: null,
  };
}

/** Full wire envelope for one list page. `cache` is only present when given —
 *  an omitted block models a payload predating the roster-cache feature. */
function listPayload(
  options: {
    orgIds?: string[];
    page?: number;
    perPage?: number;
    cache?: ColonelOrganizationsCache;
  } = {}
) {
  const { orgIds = ['org1'], page = 1, perPage = 50, cache } = options;
  return {
    record: {},
    details: {
      organizations: orgIds.map(orgRow),
      pagination: {
        page,
        per_page: perPage,
        total_count: orgIds.length,
        total_pages: 1,
      },
      filters: { status: null, sync_status: null },
      ...(cache ? { cache } : {}),
    },
  };
}

/** Manually-settled promise so a test controls the order responses arrive. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function committedOrgIds(list: ReturnType<typeof useOrganizationsList>) {
  return list.organizations.value.map((org) => org.org_id);
}

describe('useOrganizationsList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('happy path', () => {
    it('maps organizations, pagination and cacheMeta from details', async () => {
      const cache = { cached: true, generated_at: 1700000100, ttl: 90 };
      mockApi.get.mockResolvedValue({ data: listPayload({ orgIds: ['org1', 'org2'], cache }) });
      const list = useOrganizationsList();

      await list.fetchPage(1);

      expect(committedOrgIds(list)).toEqual(['org1', 'org2']);
      expect(list.pagination.value).toMatchObject({ page: 1, per_page: 50, total_count: 2 });
      expect(list.cacheMeta.value).toEqual(cache);
      expect(list.error.value).toBeNull();
      expect(list.validationError.value).toBeNull();
    });

    it('cacheMeta is null when the payload predates the cache block', async () => {
      mockApi.get.mockResolvedValue({ data: listPayload() });
      const list = useOrganizationsList();

      await list.fetchPage(1);

      expect(committedOrgIds(list)).toEqual(['org1']);
      expect(list.cacheMeta.value).toBeNull();
    });

    it('forwards server-side filters and sends refresh=1 only when bypassing', async () => {
      mockApi.get.mockResolvedValue({ data: listPayload() });
      const list = useOrganizationsList();

      await list.fetchPage(2, { status: 'active', sync_status: '', search: undefined });
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/organizations', {
        params: { page: 2, per_page: 50, status: 'active' },
      });

      await list.fetchPage(1, { search: 'acme' }, { refresh: true });
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/colonel/organizations', {
        params: { page: 1, per_page: 50, search: 'acme', refresh: '1' },
      });
    });
  });

  describe('failure-mode split (validation vs network)', () => {
    it('schema mismatch degrades to an empty table with validationError, no throw', async () => {
      mockApi.get.mockResolvedValue({ data: { record: {}, details: { organizations: 42 } } });
      const list = useOrganizationsList();

      await expect(list.fetchPage(1)).resolves.toBeUndefined();

      expect(list.organizations.value).toEqual([]);
      expect(list.pagination.value).toBeNull();
      expect(list.cacheMeta.value).toBeNull();
      expect(list.validationError.value).toBe('ColonelOrganizationsResponse');
      expect(list.error.value).toBeNull();
    });

    it('network/HTTP failure is swallowed; error drives the banner, state empties', async () => {
      const cache = { cached: true, generated_at: 1700000100, ttl: 90 };
      const list = useOrganizationsList();

      mockApi.get.mockResolvedValueOnce({ data: listPayload({ cache }) });
      await list.fetchPage(1);
      expect(committedOrgIds(list)).toEqual(['org1']);

      const httpError = new Error('Request failed with status code 500');
      mockApi.get.mockRejectedValueOnce(httpError);
      await expect(list.fetchPage(1)).resolves.toBeUndefined();

      expect(list.organizations.value).toEqual([]);
      expect(list.pagination.value).toBeNull();
      expect(list.cacheMeta.value).toBeNull();
      expect(list.error.value).toBe(httpError);
    });
  });

  describe('out-of-order responses', () => {
    it('a stale response never replaces the newer request state', async () => {
      const slow = deferred<{ data: unknown }>();
      const fast = deferred<{ data: unknown }>();
      mockApi.get
        .mockImplementationOnce(() => slow.promise)
        .mockImplementationOnce(() => fast.promise);
      const list = useOrganizationsList();

      const first = list.fetchPage(1, { search: 'acme' });
      const second = list.fetchPage(1, { search: 'zeta' });

      const freshCache = { cached: true, generated_at: 1700000200, ttl: 90 };
      fast.resolve({ data: listPayload({ orgIds: ['zeta1'], cache: freshCache }) });
      await second;
      expect(committedOrgIds(list)).toEqual(['zeta1']);

      // The obsolete search now settles — with a DIFFERENT roster, pagination
      // and cache block. None of it may reach the committed state.
      const staleCache = { cached: false, generated_at: 1700000000, ttl: 90 };
      slow.resolve({
        data: listPayload({ orgIds: ['acme1', 'acme2'], page: 7, cache: staleCache }),
      });
      await first;

      expect(committedOrgIds(list)).toEqual(['zeta1']);
      expect(list.pagination.value).toMatchObject({ page: 1, total_count: 1 });
      expect(list.cacheMeta.value).toEqual(freshCache);
      expect(list.page.value).toBe(1);
    });

    it('a stale failure neither blanks the newer rows nor plants its error', async () => {
      const slow = deferred<{ data: unknown }>();
      const fast = deferred<{ data: unknown }>();
      mockApi.get
        .mockImplementationOnce(() => slow.promise)
        .mockImplementationOnce(() => fast.promise);
      const list = useOrganizationsList();

      const first = list.fetchPage(1);
      const second = list.fetchPage(2);

      fast.resolve({ data: listPayload({ orgIds: ['fresh1'], page: 2 }) });
      await second;
      expect(committedOrgIds(list)).toEqual(['fresh1']);

      slow.reject(new Error('socket hang up'));
      await first;

      expect(committedOrgIds(list)).toEqual(['fresh1']);
      expect(list.error.value).toBeNull();
      expect(list.loading.value).toBe(false);
    });
  });
});
