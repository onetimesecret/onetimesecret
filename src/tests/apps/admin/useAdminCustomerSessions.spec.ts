// src/tests/apps/admin/useAdminCustomerSessions.spec.ts

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

import { useAdminCustomerSessions } from '@/apps/admin/stores/useAdminCustomerSessions';

const USER_ID = 'ur_abc123';

function sessionRow(overrides: Record<string, unknown> = {}) {
  return {
    session_id: 'sid_1',
    user_id: USER_ID,
    org_id: null,
    created_at: 1700000000,
    last_activity_at: 1700003600,
    ip_address: '203.0.113.7',
    user_agent: 'Mozilla/5.0',
    auth_method: 'password',
    mfa_used: null,
    ...overrides,
  };
}

function sessionsPayload(
  rows = [sessionRow(), sessionRow({ session_id: 'sid_2' })],
  currentSessionId: string | null = null
) {
  return {
    shrimp: '',
    record: {},
    details: { sessions: rows, count: rows.length, current_session_id: currentSessionId },
  };
}

function revokePayload(sessionId = 'sid_1') {
  return {
    shrimp: '',
    record: { session_id: sessionId, revoked: true },
    details: { message: 'Session revoked.' },
  };
}

function revokeAllPayload(counts = {}) {
  return {
    shrimp: '',
    record: {
      revoked: true,
      blobs_deleted: 3,
      untracked_deleted: 1,
      rodauth_rows_deleted: 0,
      scan_capped: false,
      ...counts,
    },
    details: { message: 'All sessions revoked successfully' },
  };
}

describe('useAdminCustomerSessions', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useAdminCustomerSessions().$id).toBe('adminCustomerSessions');
  });

  it('fetches the per-user sessions endpoint and parses details.sessions', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    const store = useAdminCustomerSessions();

    await store.fetchForCustomer(USER_ID);

    // The exact URL is the one thing a mock can't otherwise catch — a wrong path
    // 404s in prod but passes a naive mock. Assert it.
    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/users/ur_abc123/sessions');
    expect(store.sessions).toHaveLength(2);
    expect(store.sessions[0].session_id).toBe('sid_1');
    expect(store.sessions[0].ip_address).toBe('203.0.113.7');
    expect(store.validationError).toBeNull();
  });

  it('exposes details.current_session_id (the colonel viewing their own detail)', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, 'sid_2') });
    const store = useAdminCustomerSessions();

    await store.fetchForCustomer(USER_ID);

    expect(store.currentSessionId).toBe('sid_2');
  });

  it('defaults currentSessionId to null when the field is absent', async () => {
    // Genuinely omit the key — the schema is `.nullable().optional()`, so
    // "key missing" and "key: null" are distinct inputs. This covers missing.
    const payload = sessionsPayload();
    delete (payload.details as Record<string, unknown>).current_session_id;
    mockApi.get.mockResolvedValue({ data: payload });
    const store = useAdminCustomerSessions();

    await store.fetchForCustomer(USER_ID);

    expect(store.currentSessionId).toBeNull();
  });

  it('keeps currentSessionId null when the field is explicitly null', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload(undefined, null) });
    const store = useAdminCustomerSessions();

    await store.fetchForCustomer(USER_ID);

    expect(store.currentSessionId).toBeNull();
  });

  it('clears currentSessionId on a network failure', async () => {
    mockApi.get.mockResolvedValueOnce({ data: sessionsPayload(undefined, 'sid_2') });
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);
    expect(store.currentSessionId).toBe('sid_2');

    mockApi.get.mockRejectedValueOnce(new Error('Network Error'));
    await expect(store.fetchForCustomer(USER_ID)).rejects.toThrow('Network Error');
    expect(store.currentSessionId).toBeNull();
  });

  it('url-encodes the customer id', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload([]) });
    const store = useAdminCustomerSessions();

    await store.fetchForCustomer('ur/weird id');

    expect(mockApi.get).toHaveBeenCalledWith(
      '/api/colonel/users/ur%2Fweird%20id/sessions'
    );
  });

  it('degrades to empty and sets validationError on a schema mismatch', async () => {
    mockApi.get.mockResolvedValue({ data: { shrimp: '', record: {}, details: { sessions: 'nope' } } });
    const store = useAdminCustomerSessions();

    const result = await store.fetchForCustomer(USER_ID);

    expect(result).toBeNull();
    expect(store.sessions).toEqual([]);
    expect(store.validationError).toBe('ColonelCustomerSessionsResponse');
  });

  it('clears rows and rethrows on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    const store = useAdminCustomerSessions();

    await expect(store.fetchForCustomer(USER_ID)).rejects.toThrow('Network Error');
    expect(store.sessions).toEqual([]);
    expect(store.error).toBeInstanceOf(Error);
  });

  it('revoke DELETEs the per-session endpoint and optimistically drops the row', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    mockApi.delete.mockResolvedValue({ data: revokePayload('sid_1') });
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);
    expect(store.sessions).toHaveLength(2);

    await store.revoke(USER_ID, 'sid_1');

    expect(mockApi.delete).toHaveBeenCalledWith(
      '/api/colonel/users/ur_abc123/sessions/sid_1'
    );
    expect(store.sessions).toHaveLength(1);
    expect(store.sessions.map((s) => s.session_id)).toEqual(['sid_2']);
  });

  it('keeps the row when revoke rejects', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    mockApi.delete.mockRejectedValue(new Error('403'));
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);

    await expect(store.revoke(USER_ID, 'sid_1')).rejects.toThrow('403');
    expect(store.sessions).toHaveLength(2);
  });

  it('revokeAll POSTs the revoke-all endpoint, clears the list, and returns kill counts', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    mockApi.post.mockResolvedValue({ data: revokeAllPayload() });
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);
    expect(store.sessions).toHaveLength(2);

    const record = await store.revokeAll(USER_ID);

    // Wrong path 404s in prod but passes a naive mock — assert it. POST, not DELETE.
    expect(mockApi.post).toHaveBeenCalledWith(
      '/api/colonel/users/ur_abc123/sessions/revoke-all'
    );
    expect(store.sessions).toEqual([]);
    expect(record.blobs_deleted).toBe(3);
    expect(record.untracked_deleted).toBe(1);
  });

  it('revokeAll still clears the list on ack drift (schema-mismatch fallback)', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    mockApi.post.mockResolvedValue({ data: { shrimp: '', record: { revoked: 'yes' }, details: {} } });
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);

    const record = await store.revokeAll(USER_ID);

    expect(store.sessions).toEqual([]);
    // Drift degrades to the zero-count fallback rather than throwing.
    expect(record).toEqual({
      revoked: true,
      blobs_deleted: 0,
      untracked_deleted: 0,
      rodauth_rows_deleted: 0,
      scan_capped: false,
    });
  });

  it('revokeAll rethrows and keeps the list on a network failure', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    mockApi.post.mockRejectedValue(new Error('403'));
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);

    await expect(store.revokeAll(USER_ID)).rejects.toThrow('403');
    expect(store.sessions).toHaveLength(2);
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: sessionsPayload() });
    const store = useAdminCustomerSessions();
    await store.fetchForCustomer(USER_ID);
    expect(store.sessions).toHaveLength(2);

    store.$reset();

    expect(store.sessions).toEqual([]);
    expect(store.error).toBeNull();
    expect(store.validationError).toBeNull();
  });
});
