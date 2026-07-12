// src/tests/apps/admin/useAdminOrganizations.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => mockApi,
}));

import { useAdminOrganizations } from '@/apps/admin/stores/useAdminOrganizations';

function orgRow(overrides: Record<string, unknown> = {}) {
  return {
    org_id: 'org1',
    extid: 'on_abc123',
    display_name: 'Acme',
    contact_email: 'owner@acme.test',
    owner_id: 'cust1',
    owner_email: 'ow***@a***.test',
    member_count: 3,
    domain_count: 1,
    is_default: false,
    created: 1700000000,
    updated: 1700003600,
    planid: 'identity_plus_v1',
    stripe_customer_id: 'cus_123',
    stripe_subscription_id: 'sub_123',
    subscription_status: 'active',
    subscription_period_end: '2026-01-01',
    billing_email: 'billing@acme.test',
    sync_status: 'potentially_stale',
    sync_status_reason: 'planid differs from Stripe',
    ...overrides,
  };
}

function orgsPayload(rows = [orgRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      organizations: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
      filters: { status: null, sync_status: null },
    },
  };
}

describe('useAdminOrganizations', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminOrganizations().$id).toBe('adminOrganizations');
  });

  it('fetches the organizations endpoint and maps the page via its own selector', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    const store = useAdminOrganizations();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.organizations).toHaveLength(1);
    expect(store.organizations[0].extid).toBe('on_abc123');
    expect(store.organizations[0].created).toBeInstanceOf(Date);
    expect(store.pagination?.total_count).toBe(1);
  });

  it('threads the subscription + sync-status filters through as query params', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    const store = useAdminOrganizations();

    await store.fetchPage(2, { status: 'past_due', sync_status: 'potentially_stale' });

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations', {
      params: { page: 2, per_page: 50, status: 'past_due', sync_status: 'potentially_stale' },
    });
  });

  it('drops empty filters (no phantom query params)', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    const store = useAdminOrganizations();

    await store.fetchPage(1, { status: '', sync_status: undefined });

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/organizations', {
      params: { page: 1, per_page: 50 },
    });
  });

  it('clears rows and rethrows on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    const store = useAdminOrganizations();

    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');
    expect(store.organizations).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.error).toBeInstanceOf(Error);
  });

  it('degrades to empty (no throw) on a schema mismatch', async () => {
    mockApi.get.mockResolvedValue({
      data: { shrimp: '', record: {}, details: { organizations: 'nope' } },
    });
    const store = useAdminOrganizations();

    const result = await store.fetchPage(1);
    expect(result).toBeNull();
    expect(store.organizations).toEqual([]);
    expect(store.validationError).toBe('ColonelOrganizationsResponse');
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: orgsPayload() });
    const store = useAdminOrganizations();
    await store.fetchPage(1);
    expect(store.organizations).toHaveLength(1);

    store.$reset();

    expect(store.organizations).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });
});
