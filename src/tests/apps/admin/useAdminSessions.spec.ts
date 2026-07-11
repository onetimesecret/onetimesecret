// src/tests/apps/admin/useAdminSessions.spec.ts

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

import { useAdminSessions } from '@/apps/admin/stores/useAdminSessions';

function sessionsPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      sessions: [
        {
          session_id: 'sid_1',
          key: 'session:sid_1',
          authenticated: true,
          email: 'alice@example.com',
          external_id: 'ext_1',
          role: 'customer',
          ip_address: '203.0.113.7',
          user_agent: 'Mozilla/5.0',
          created_at: 1700000000,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
      // Keyspace scan meta (list_sessions.rb success_data.details.scan).
      scan: { scanned: 64, anonymous_count: 63, scan_capped: false },
    },
  };
}

describe('useAdminSessions', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminSessions().$id).toBe('adminSessions');
  });

  it('fetches the sessions endpoint and maps the page via its own selector', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    const store = useAdminSessions();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/sessions', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.sessions).toHaveLength(1);
    expect(store.sessions[0].session_id).toBe('sid_1');
    expect(store.pagination?.total_count).toBe(1);
  });

  it('passes the search term through as a server query param', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    const store = useAdminSessions();

    await store.fetchPage(1, 'alice@example.com');

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/sessions', {
      params: { page: 1, per_page: 50, search: 'alice@example.com' },
    });
  });

  it('clears rows and rethrows on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    const store = useAdminSessions();

    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');
    expect(store.sessions).toEqual([]);
    expect(store.pagination).toBeNull();
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    const store = useAdminSessions();
    await store.fetchPage(1);
    expect(store.sessions).toHaveLength(1);

    store.$reset();

    expect(store.sessions).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });
});
