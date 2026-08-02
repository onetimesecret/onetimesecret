// src/tests/shared/composables/useOrgAuditEvents.spec.ts

/**
 * useOrgAuditEvents (#3637) — read-time actor identity resolution.
 *
 * The composable's paging/error/validation behavior is exercised end-to-end
 * through SecretActivityTable.spec.ts (real composable, real schema, mocked
 * HTTP). This spec covers the `actors` contract in isolation: the schema
 * must accept responses WITH and WITHOUT `details.actors` (older backends
 * omit it), and the exposed map must default to {} so lookups of unresolved
 * actors fall through to the bare objid.
 */

import { useOrgAuditEvents } from '@/shared/composables/useOrgAuditEvents';
import { flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const mockApi = {
  get: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({
    message: err instanceof Error ? err.message : 'Unknown error',
  }),
}));

// Full customer objid — the wire format for actor_id since #3637.
const FULL_ACTOR_OBJID = '0198c0ffee15deadbeef4b1dfacade42';

const buildEvent = (overrides: Record<string, unknown> = {}) => ({
  kind: 'revealed',
  at: 1754049600,
  nonce: 'nonce-1',
  secret: 'abcd1234',
  actor: 'authenticated_other',
  actor_id: FULL_ACTOR_OBJID,
  ...overrides,
});

const buildResponse = (
  details: Record<string, unknown> = { offset: 0, limit: 50 },
  records: object[] = [buildEvent()]
) => ({
  user_id: 'usr_123',
  organization_id: 'org_123',
  records,
  count: records.length,
  total: records.length,
  details,
});

describe('useOrgAuditEvents — actors resolution map', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('exposes an empty actors map before any fetch', () => {
    const { actors } = useOrgAuditEvents(ref('on1abc123'));

    expect(actors.value).toEqual({});
  });

  it('accepts a response WITH details.actors and exposes the map', async () => {
    const resolution = {
      [FULL_ACTOR_OBJID]: { email: 'alice@example.com', extid: 'cx1abc123' },
    };
    mockApi.get.mockResolvedValue({
      data: buildResponse({ offset: 0, limit: 50, actors: resolution }),
    });

    const { actors, records, validationError, fetchPage } = useOrgAuditEvents(ref('on1abc123'));
    await fetchPage(0);
    await flushPromises();

    expect(validationError.value).toBe(false);
    expect(records.value).toHaveLength(1);
    expect(actors.value).toEqual(resolution);
  });

  it('accepts a response WITHOUT details.actors (older backend) and defaults to {}', async () => {
    mockApi.get.mockResolvedValue({ data: buildResponse() });

    const { actors, records, validationError, fetchPage } = useOrgAuditEvents(ref('on1abc123'));
    await fetchPage(0);
    await flushPromises();

    expect(validationError.value).toBe(false);
    expect(records.value).toHaveLength(1);
    expect(actors.value).toEqual({});
  });

  it('replaces a stale map on the next page fetch instead of merging', async () => {
    const pageOne = {
      [FULL_ACTOR_OBJID]: { email: 'alice@example.com', extid: 'cx1abc123' },
    };
    mockApi.get.mockResolvedValueOnce({
      data: buildResponse({ offset: 0, limit: 50, actors: pageOne }),
    });
    mockApi.get.mockResolvedValueOnce({
      data: buildResponse({ offset: 50, limit: 50 }),
    });

    const { actors, fetchPage, next } = useOrgAuditEvents(ref('on1abc123'));
    await fetchPage(0);
    await flushPromises();
    expect(actors.value).toEqual(pageOne);

    // Page 2 arrives without a map — a resolution from page 1 must not leak
    // into lookups against page 2's rows.
    await next();
    await flushPromises();
    expect(actors.value).toEqual({});
  });

  it('clears the map on a contract mismatch alongside records', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mockApi.get.mockResolvedValueOnce({
      data: buildResponse({ offset: 0, limit: 50, actors: {} }),
    });
    // Malformed actors entry (missing email) → schema failure.
    mockApi.get.mockResolvedValueOnce({
      data: buildResponse({
        offset: 0,
        limit: 50,
        actors: { [FULL_ACTOR_OBJID]: { extid: 'cx1abc123' } },
      }),
    });

    const { actors, validationError, fetchPage, refresh } = useOrgAuditEvents(ref('on1abc123'));
    await fetchPage(0);
    await flushPromises();
    expect(validationError.value).toBe(false);

    await refresh();
    await flushPromises();
    expect(validationError.value).toBe(true);
    expect(actors.value).toEqual({});
  });
});

describe('useOrgAuditEvents — abort and superseded-request handling', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('abort() clears isLoading when no new fetch follows (unmount path)', async () => {
    // A request that never settles — abort() is the only way out.
    mockApi.get.mockImplementation(() => new Promise(() => {}));

    const { isLoading, fetchPage, abort } = useOrgAuditEvents(ref('on1abc123'));
    void fetchPage(0);
    expect(isLoading.value).toBe(true);

    abort();
    await flushPromises();
    expect(isLoading.value).toBe(false);
  });

  it('does not apply a response whose request was superseded after completion', async () => {
    const staleActors = {
      [FULL_ACTOR_OBJID]: { email: 'stale@example.com', extid: 'cx1stale' },
    };
    // First request resolves successfully, but only AFTER a second fetch has
    // superseded it (axios resolves rather than rejects when the abort lands
    // after the response) — its data must never overwrite current state.
    let resolveFirst!: (value: unknown) => void;
    mockApi.get
      .mockImplementationOnce(() => new Promise((resolve) => { resolveFirst = resolve; }))
      .mockResolvedValueOnce({
        data: buildResponse({ offset: 0, limit: 50, actors: {} }, [
          buildEvent({ nonce: 'fresh-1' }),
        ]),
      });

    const { records, actors, fetchPage } = useOrgAuditEvents(ref('on1abc123'));
    const first = fetchPage(0);
    const second = fetchPage(0); // supersedes (and aborts) the first

    // First request's response arrives late, after being superseded.
    resolveFirst({
      data: buildResponse({ offset: 0, limit: 50, actors: staleActors }, [
        buildEvent({ nonce: 'stale-1' }),
      ]),
    });
    await Promise.all([first, second]);
    await flushPromises();

    expect(records.value.map((r) => r.nonce)).toEqual(['fresh-1']);
    expect(actors.value).toEqual({});
  });
});
