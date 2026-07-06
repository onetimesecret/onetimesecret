// src/tests/apps/admin/useAdminSecrets.spec.ts

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

import { useAdminSecrets } from '@/apps/admin/stores/useAdminSecrets';

function secretsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      secrets: [
        {
          secret_id: 's1',
          shortid: 'abc123',
          owner_id: 'ext_owner',
          state: 'new',
          created: 1700000000,
          expiration: 1700003600,
          lifespan: 3600,
          receipt_id: 'r1',
          age: 120,
          has_ciphertext: true,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
    },
  };
}

describe('useAdminSecrets', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminSecrets().$id).toBe('adminSecrets');
  });

  it('fetches the secrets endpoint and maps the page via its own selector', async () => {
    mockApi.get.mockResolvedValue({ data: secretsPayload() });
    const store = useAdminSecrets();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/secrets', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.secrets).toHaveLength(1);
    expect(store.secrets[0].shortid).toBe('abc123');
    expect(store.secrets[0].created).toBeInstanceOf(Date);
    expect(store.pagination?.total_count).toBe(1);
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: secretsPayload() });
    const store = useAdminSecrets();
    await store.fetchPage(1);
    expect(store.secrets).toHaveLength(1);

    store.$reset();

    expect(store.secrets).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });
});
