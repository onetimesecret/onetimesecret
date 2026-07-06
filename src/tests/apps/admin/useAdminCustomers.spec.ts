// src/tests/apps/admin/useAdminCustomers.spec.ts

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

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

import { useAdminCustomers } from '@/apps/admin/stores/useAdminCustomers';
import { useAdminSecrets } from '@/apps/admin/stores/useAdminSecrets';

// A wire-shape colonel users response (numbers for date fields, matching the
// real endpoint) so the REAL colonelUsersResponseSchema — including its
// transforms — runs unchanged.
function usersPayload(overrides: { page?: number; per_page?: number } = {}) {
  return {
    shrimp: '',
    record: {},
    details: {
      users: [
        {
          user_id: 'u1',
          extid: 'ext_abc',
          email: 'user@example.com',
          role: 'customer',
          verified: true,
          created: 1700000000,
          last_login: 1700000100,
          planid: 'basic',
          secrets_count: 3,
          secrets_created: 5,
          secrets_shared: 2,
        },
      ],
      pagination: {
        page: overrides.page ?? 1,
        per_page: overrides.per_page ?? 50,
        total_count: 1,
        total_pages: 1,
      },
    },
  };
}

describe('useAdminCustomers', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id distinct from the retiring colonel god-store', () => {
    const store = useAdminCustomers();
    expect(store.$id).toBe('adminCustomers');
    expect(store.$id).not.toBe('colonel');
  });

  it('starts empty with initial fetch state', () => {
    const store = useAdminCustomers();
    expect(store.customers).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.loading).toBe(false);
    expect(store.error).toBeNull();
    expect(store.validationError).toBeNull();
    expect(store.page).toBe(1);
    expect(store.perPage).toBe(50);
  });

  it('fetches the users endpoint with page/per_page and maps the page', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    const store = useAdminCustomers();

    const result = await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users', {
      params: { page: 1, per_page: 50 },
    });
    expect(result).not.toBeNull();
    expect(store.customers).toHaveLength(1);
    expect(store.customers[0].email).toBe('user@example.com');
    expect(store.pagination).toEqual({
      page: 1,
      per_page: 50,
      total_count: 1,
      total_pages: 1,
    });
  });

  it('runs the real schema transforms (created becomes a Date)', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    const store = useAdminCustomers();

    await store.fetchPage(1);

    expect(store.customers[0].created).toBeInstanceOf(Date);
    expect(store.customers[0].last_login).toBeInstanceOf(Date);
  });

  it('forwards a role filter as a server query param', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    const store = useAdminCustomers();

    await store.fetchPage(2, 'colonel');

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users', {
      params: { page: 2, per_page: 50, role: 'colonel' },
    });
  });

  it('degrades to empty on a schema mismatch without throwing', async () => {
    mockApi.get.mockResolvedValue({ data: { record: {}, details: { users: 'nope' } } });
    const store = useAdminCustomers();

    const result = await store.fetchPage(1);

    expect(result).toBeNull();
    expect(store.customers).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.validationError).toBe('ColonelUsersResponse');
    expect(store.error).toBeNull();
  });

  it('clears rows and rethrows on a network/HTTP error', async () => {
    // Seed a successful page first so we can prove stale rows get cleared.
    mockApi.get.mockResolvedValueOnce({ data: usersPayload() });
    const store = useAdminCustomers();
    await store.fetchPage(1);
    expect(store.customers).toHaveLength(1);

    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    await expect(store.fetchPage(2)).rejects.toThrow('Network Error');

    expect(store.customers).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.error).toBeInstanceOf(Error);
    expect(store.error?.message).toBe('Network Error');
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload({ page: 3, per_page: 25 }) });
    const store = useAdminCustomers();
    await store.fetchPage(3);
    expect(store.customers).toHaveLength(1);
    expect(store.page).toBe(3);

    store.$reset();

    expect(store.customers).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
    expect(store.perPage).toBe(50);
    expect(store.validationError).toBeNull();
  });

  it('coexists with a sibling resource store without state collision', async () => {
    mockApi.get.mockResolvedValue({ data: usersPayload() });
    const customers = useAdminCustomers();
    const secrets = useAdminSecrets();

    expect(customers.$id).toBe('adminCustomers');
    expect(secrets.$id).toBe('adminSecrets');
    expect(customers.$id).not.toBe(secrets.$id);

    await customers.fetchPage(1);
    // The customers fetch must not have populated the secrets store.
    expect(secrets.secrets).toEqual([]);
  });
});

describe('useAdminCustomers — import isolation (CONTRACT 3)', () => {
  const adminRoot = resolve(process.cwd(), 'src/apps/admin');
  const files = [
    resolve(adminRoot, 'composables/usePaginatedFetch.ts'),
    resolve(adminRoot, 'stores/useAdminCustomers.ts'),
    resolve(adminRoot, 'stores/useAdminSecrets.ts'),
  ];

  it.each(files)('%s has ZERO import edge into the retiring colonel tree', (file) => {
    const source = readFileSync(file, 'utf8');
    const importLines = source
      .split('\n')
      .filter((line) => /^\s*import[\s{]/.test(line) || /\bfrom\s+['"]/.test(line));
    const joined = importLines.join('\n');

    expect(joined).not.toMatch(/apps\/colonel/);
    expect(joined).not.toMatch(/colonelInfoStore/);
  });
});
