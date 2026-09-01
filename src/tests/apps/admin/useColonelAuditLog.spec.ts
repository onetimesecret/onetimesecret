// src/tests/apps/admin/useColonelAuditLog.spec.ts

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

import { useColonelAuditLog } from '@/apps/admin/stores/useColonelAuditLog';

function auditPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      events: [
        {
          id: 'evt_1',
          actor: 'ur_colonel1',
          verb: 'customer.set_role',
          target: 'ur_target1',
          result: 'success',
          detail: { from: 'customer', to: 'admin' },
          created: 1700000000.25,
          // Stream discriminator (#4335). Required by colonelAuditEventSchema.
          trail: 'events',
        },
      ],
      pagination: {
        page: 1,
        per_page: 50,
        total_count: 1,
        total_pages: 1,
        actor: null,
        verb: null,
      },
    },
  };
}

describe('useColonelAuditLog', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('uses a unique store id', () => {
    expect(useColonelAuditLog().$id).toBe('colonelAuditLog');
  });

  it('fetches the audit endpoint and maps the page via its own selector', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    const store = useColonelAuditLog();

    await store.fetchPage(1);

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/audit', {
      params: { page: 1, per_page: 50 },
    });
    expect(store.events).toHaveLength(1);
    expect(store.events[0].verb).toBe('customer.set_role');
    // The Unix-second float arrives as a Date after the Zod transform.
    expect(store.events[0].created).toBeInstanceOf(Date);
    expect(store.pagination?.total_count).toBe(1);
  });

  it('passes actor and verb filters through as server query params', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    const store = useColonelAuditLog();

    await store.fetchPage(1, { actor: 'ur_colonel1', verb: 'customer' });

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/audit', {
      params: { page: 1, per_page: 50, actor: 'ur_colonel1', verb: 'customer' },
    });
  });

  it('omits empty filters from the query', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    const store = useColonelAuditLog();

    await store.fetchPage(1, { actor: '', verb: undefined });

    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/audit', {
      params: { page: 1, per_page: 50 },
    });
  });

  it('degrades to empty on a schema mismatch (validationError, no throw)', async () => {
    mockApi.get.mockResolvedValue({ data: { details: { events: 'not-an-array' } } });
    const store = useColonelAuditLog();

    const result = await store.fetchPage(1);

    expect(result).toBeNull();
    expect(store.events).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.validationError).toBe('ColonelAuditEventsResponse');
  });

  it('clears rows and rethrows on a network failure', async () => {
    mockApi.get.mockRejectedValue(new Error('Network Error'));
    const store = useColonelAuditLog();

    await expect(store.fetchPage(1)).rejects.toThrow('Network Error');
    expect(store.events).toEqual([]);
    expect(store.pagination).toBeNull();
  });

  // The export endpoint is a download, not a fetch: the store only has to
  // build the URL (with the active filters) for the view to link to.
  describe('exportUrl', () => {
    it('targets the export endpoint with the requested format', () => {
      expect(useColonelAuditLog().exportUrl('csv')).toBe(
        '/api/colonel/audit/export?format=csv'
      );
      expect(useColonelAuditLog().exportUrl('ndjson')).toBe(
        '/api/colonel/audit/export?format=ndjson'
      );
    });

    it('carries the active filters so the file matches the table', () => {
      const url = useColonelAuditLog().exportUrl('csv', {
        actor: 'colonel@example.com',
        verb: 'customer',
      });

      expect(url).toBe(
        '/api/colonel/audit/export?format=csv&actor=colonel%40example.com&verb=customer'
      );
    });

    it('omits empty filters rather than sending blanks', () => {
      expect(useColonelAuditLog().exportUrl('csv', { actor: '', verb: undefined })).toBe(
        '/api/colonel/audit/export?format=csv'
      );
    });

    it('never issues a request of its own', () => {
      useColonelAuditLog().exportUrl('csv');

      expect(mockApi.get).not.toHaveBeenCalled();
    });
  });

  it('$reset restores initial state', async () => {
    mockApi.get.mockResolvedValue({ data: auditPayload() });
    const store = useColonelAuditLog();
    await store.fetchPage(1);
    expect(store.events).toHaveLength(1);

    store.$reset();

    expect(store.events).toEqual([]);
    expect(store.pagination).toBeNull();
    expect(store.page).toBe(1);
  });
});
