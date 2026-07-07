// src/tests/apps/admin/sessionSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelSessionsResponseSchema,
  colonelSessionDetailResponseSchema,
  colonelSessionDeleteResponseSchema,
} from '@/schemas/api/internal/responses/colonel-sessions';

/**
 * Zod tripwire (CONTRACT 3) for the three NEW Sessions-console contracts. These
 * payloads are shaped exactly as the live logic classes emit them — verified
 * against apps/api/colonel/logic/colonel/{list_sessions,get_session_detail,
 * delete_session}.rb, thin adapters over Onetime::Operations::Sessions::*. If a
 * backend response drifts, these fail rather than the screen silently breaking.
 */

// ListSessions `success_data`, on the wire (bare-number epoch fields).
function listPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      sessions: [
        {
          session_id: 'sid_auth',
          key: 'session:sid_auth',
          authenticated: true,
          email: 'alice@example.com',
          external_id: 'ext_1',
          role: 'customer',
          ip_address: '203.0.113.7',
          created_at: 1700000000,
        },
        {
          session_id: 'sid_anon',
          key: 'session:sid_anon',
          authenticated: false,
          email: null,
          external_id: null,
          role: null,
          ip_address: null,
          created_at: null,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
    },
  };
}

describe('colonelSessionsResponseSchema (ListSessions)', () => {
  it('parses the list payload including an anonymous (all-null) session row', () => {
    const result = colonelSessionsResponseSchema.safeParse(listPayload());
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details?.sessions).toHaveLength(2);
    expect(result.data.details?.sessions[1].email).toBeNull();
    expect(result.data.details?.sessions[1].created_at).toBeNull();
    expect(result.data.details?.pagination.total_count).toBe(2);
  });

  it('rejects a row missing the required authenticated flag (contract drift)', () => {
    const payload = listPayload() as unknown as {
      details: { sessions: Array<{ authenticated?: boolean }> };
    };
    delete payload.details.sessions[0].authenticated;
    expect(colonelSessionsResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('colonelSessionDetailResponseSchema (GetSessionDetail)', () => {
  function detailPayload() {
    return {
      shrimp: '',
      record: {
        session_id: 'sid_auth',
        key: 'session:sid_auth',
        ttl: 3600,
        authenticated: true,
        email: 'alice@example.com',
        external_id: 'ext_1',
        account_id: 42,
        role: 'customer',
        locale: 'en',
        ip_address: '203.0.113.7',
        authenticated_at: 1700000000,
        authenticated_by: 'password',
        active_session_id: 'as_1',
      },
      details: {
        data: { authenticated: true, email: 'alice@example.com', csrf: 'abc' },
      },
    };
  }

  it('parses the detail payload with a numeric account_id and open raw data', () => {
    const result = colonelSessionDetailResponseSchema.safeParse(detailPayload());
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.ttl).toBe(3600);
    expect(result.data.record.account_id).toBe(42);
    expect(result.data.details?.data.email).toBe('alice@example.com');
  });

  it('accepts an anonymous session: -1 ttl and null identity fields', () => {
    const payload = detailPayload();
    payload.record.ttl = -1;
    payload.record.email = null as never;
    payload.record.external_id = null as never;
    payload.record.account_id = null as never;
    payload.record.authenticated = false;
    payload.record.authenticated_at = null as never;
    payload.record.authenticated_by = null as never;
    payload.record.active_session_id = null as never;
    const result = colonelSessionDetailResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.ttl).toBe(-1);
    expect(result.data.record.account_id).toBeNull();
  });
});

describe('colonelSessionDeleteResponseSchema (DeleteSession)', () => {
  it('validates the revoke ack', () => {
    const payload = {
      shrimp: '',
      record: { session_id: 'sid_auth', deleted: true },
      details: { message: 'Session revoked successfully' },
    };
    const result = colonelSessionDeleteResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.deleted).toBe(true);
  });

  it('rejects an ack missing details.message', () => {
    const payload = {
      record: { session_id: 'sid_auth', deleted: true },
      details: {},
    };
    expect(colonelSessionDeleteResponseSchema.safeParse(payload).success).toBe(false);
  });
});
