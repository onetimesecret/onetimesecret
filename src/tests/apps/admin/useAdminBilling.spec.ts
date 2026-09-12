// src/tests/apps/admin/useAdminBilling.spec.ts

import { AxiosError } from 'axios';
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

import { STRIPE_ORGANIZATIONS_URL, useAdminBilling } from '@/apps/admin/stores/useAdminBilling';
import type { ColonelStripeOrganization } from '@/schemas/api/internal/responses/colonel-billing';

/** Build a real AxiosError so the store can read `response.status`. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

function orgRow(overrides: Partial<ColonelStripeOrganization> = {}): ColonelStripeOrganization {
  return {
    org_id: 'org1',
    extid: 'og_abc123',
    display_name: 'Acme',
    owner_email: 'owner@acme.test',
    billing_email: 'billing@acme.test',
    planid: 'identity_plus_v1',
    stripe_customer_id: 'cus_123',
    stripe_subscription_id: 'sub_123',
    subscription_status: 'active',
    subscription_period_end: '2026-01-01',
    sync_status: 'synced',
    ...overrides,
  };
}

// Only `extid` + `stripe_customer_id` are required on the wire (see
// colonelStripeOrganizationSchema); every other field is nullish, so a row
// array may legitimately mix full rows with sparse ones.
function payload(rows: ColonelStripeOrganization[] = [orgRow()]) {
  return {
    shrimp: '',
    record: {},
    details: {
      organizations: rows,
      pagination: { page: 1, per_page: 50, total_count: rows.length, total_pages: 1 },
      filters: { search: null },
    },
  };
}

describe('useAdminBilling (Stripe customers roster)', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminBilling().$id).toBe('adminBilling');
  });

  it('fetches the index-backed roster endpoint and maps the page', async () => {
    mockApi.get.mockResolvedValue({ data: payload() });
    const store = useAdminBilling();

    await store.fetchStripeOrganizations(1);

    expect(mockApi.get).toHaveBeenCalledWith(STRIPE_ORGANIZATIONS_URL, {
      params: { page: 1, per_page: 50 },
    });
    expect(store.stripeOrganizations).toHaveLength(1);
    expect(store.stripeOrganizations[0].stripe_customer_id).toBe('cus_123');
    expect(store.pagination).toEqual({
      page: 1,
      per_page: 50,
      total_count: 1,
      total_pages: 1,
    });
  });

  it('threads the search filter through and drops it when empty', async () => {
    mockApi.get.mockResolvedValue({ data: payload() });
    const store = useAdminBilling();

    await store.fetchStripeOrganizations(2, { search: 'cus_1' });
    expect(mockApi.get).toHaveBeenLastCalledWith(STRIPE_ORGANIZATIONS_URL, {
      params: { page: 2, per_page: 50, search: 'cus_1' },
    });

    await store.fetchStripeOrganizations(1, { search: '' });
    expect(mockApi.get).toHaveBeenLastCalledWith(STRIPE_ORGANIZATIONS_URL, {
      params: { page: 1, per_page: 50 },
    });
  });

  it('degrades to empty (no throw) on a contract mismatch', async () => {
    mockApi.get.mockResolvedValue({ data: { shrimp: '', record: {}, details: { nope: true } } });
    const store = useAdminBilling();

    await expect(store.fetchStripeOrganizations(1)).resolves.toBeNull();
    expect(store.stripeOrganizations).toEqual([]);
    expect(store.validationError).toBe('ColonelStripeOrganizationsResponse');
    expect(store.error).toBeNull();
  });

  it('flags a 404 as unavailable and suppresses the failure banner', async () => {
    mockApi.get.mockRejectedValue(axiosError(404, { error: 'Not Found' }));
    const store = useAdminBilling();

    // A backend without the endpoint is a known deployment state, not a failure
    // the operator can retry away — so it resolves instead of throwing.
    await expect(store.fetchStripeOrganizations(1)).resolves.toBeNull();
    expect(store.unavailable).toBe(true);
    expect(store.error).toBeNull();
    expect(store.stripeOrganizations).toEqual([]);
  });

  it('clears rows and rethrows a real network failure', async () => {
    mockApi.get.mockResolvedValue({ data: payload() });
    const store = useAdminBilling();
    await store.fetchStripeOrganizations(1);
    expect(store.stripeOrganizations).toHaveLength(1);

    mockApi.get.mockRejectedValue(new Error('Network Error'));
    await expect(store.fetchStripeOrganizations(1)).rejects.toThrow('Network Error');
    expect(store.stripeOrganizations).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.unavailable).toBe(false);
    expect(store.error).toBeInstanceOf(Error);
  });

  it('clears the unavailable flag once the endpoint answers', async () => {
    mockApi.get.mockRejectedValue(axiosError(404, {}));
    const store = useAdminBilling();
    await store.fetchStripeOrganizations(1);
    expect(store.unavailable).toBe(true);

    mockApi.get.mockResolvedValue({ data: payload() });
    await store.fetchStripeOrganizations(1);
    expect(store.unavailable).toBe(false);
    expect(store.stripeOrganizations).toHaveLength(1);
  });

  it('reads the bound signals from the pagination envelope', async () => {
    const body = payload();
    Object.assign(body.details.pagination, { capped: true, stale_count: 3 });
    mockApi.get.mockResolvedValue({ data: body });
    const store = useAdminBilling();

    await store.fetchStripeOrganizations(1);
    expect(store.capped).toBe(true);
    expect(store.staleCount).toBe(3);
  });

  it('falls back to the details root for the bound signals', async () => {
    // The HTTP adapter is landing concurrently; accept either placement rather
    // than silently under-reporting a capped scan.
    const body = payload();
    Object.assign(body.details, { capped: true, stale_count: 1 });
    mockApi.get.mockResolvedValue({ data: body });
    const store = useAdminBilling();

    await store.fetchStripeOrganizations(1);
    expect(store.capped).toBe(true);
    expect(store.staleCount).toBe(1);
  });

  it('accepts a sparse row (only the two identity fields)', async () => {
    mockApi.get.mockResolvedValue({
      data: payload([{ extid: 'og_minimal', stripe_customer_id: 'cus_MIN' }]),
    });
    const store = useAdminBilling();

    await store.fetchStripeOrganizations(1);
    expect(store.validationError).toBeNull();
    expect(store.stripeOrganizations[0].display_name).toBeUndefined();
  });

  it('$reset clears rows, pagination, page state and the unavailable flag', async () => {
    mockApi.get.mockResolvedValue({ data: payload() });
    const store = useAdminBilling();
    await store.fetchStripeOrganizations(1);

    store.$reset();
    expect(store.stripeOrganizations).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.unavailable).toBe(false);
    expect(store.page).toBe(1);
    expect(store.perPage).toBe(50);
  });
});
