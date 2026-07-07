// src/tests/apps/admin/useAdminDomains.spec.ts

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

import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';

function domainRow(overrides: Record<string, unknown> = {}) {
  return {
    domain_id: 'cd1',
    extid: 'cd_abc123',
    display_domain: 'secrets.example.com',
    base_domain: 'example.com',
    subdomain: 'secrets',
    status: null,
    verified: true,
    resolving: true,
    verification_state: 'verified',
    ready: true,
    created: 1700000000,
    updated: 1700003600,
    org_id: 'org1',
    org_name: 'Acme',
    brand: { name: 'Acme', tagline: null, homepage_url: null },
    homepage_config: null,
    api_config: null,
    has_logo: false,
    has_icon: false,
    logo_url: null,
    icon_url: null,
    ...overrides,
  };
}

function domainsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      domains: [domainRow()],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
    },
  };
}

describe('useAdminDomains', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminDomains().$id).toBe('adminDomains');
  });

  it('fetches the domains endpoint and maps the page via its own selector', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    const store = useAdminDomains();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/domains', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.domains).toHaveLength(1);
    expect(store.domains[0].display_domain).toBe('secrets.example.com');
    expect(store.domains[0].created).toBeInstanceOf(Date);
    expect(store.pagination?.total_count).toBe(1);
  });

  it('clears rows and rethrows on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    const store = useAdminDomains();

    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');
    expect(store.domains).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.error).toBeInstanceOf(Error);
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: domainsPayload() });
    const store = useAdminDomains();
    await store.fetchPage(1);
    expect(store.domains).toHaveLength(1);

    store.$reset();

    expect(store.domains).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });
});
