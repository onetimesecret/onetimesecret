// src/tests/apps/admin/sessionSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelSessionsResponseSchema,
  colonelSessionDetailResponseSchema,
  colonelSessionDeleteResponseSchema,
} from '@/schemas/api/internal/responses/colonel-sessions';

const HANDLE = '0123456789abcdef0123456789abcdef';
const HANDLE_B = 'fedcba9876543210fedcba9876543210';
/** The raw sid shape the console must never see again (#4330). */
const RAW_SID = 'a'.repeat(64);

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
          session_handle: HANDLE,
          authenticated: true,
          email: 'alice@example.com',
          external_id: 'ext_1',
          role: 'customer',
          ip_address: '203.0.113.7',
          user_agent: 'Mozilla/5.0',
          created_at: 1700000000,
        },
        {
          session_handle: HANDLE_B,
          authenticated: false,
          email: null,
          external_id: null,
          role: null,
          ip_address: null,
          user_agent: null,
          created_at: null,
        },
      ],
      pagination: { page: 1, per_page: 50, total_count: 2, total_pages: 1 },
      // Keyspace scan meta (list_sessions.rb success_data.details.scan).
      scan: { scanned: 128, anonymous_count: 126, scan_capped: false },
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

  it('parses geo_country as a resolved code or a null — the only shapes the API emits', () => {
    // Otto's '**' unknown sentinel is normalized to null server-side and never
    // crosses the API.
    const payload = listPayload();
    const rows = payload.details.sessions as Array<Record<string, unknown>>;
    rows[0].geo_country = 'DE';
    rows[1].geo_country = null;

    const result = colonelSessionsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    const parsed = result.data.details?.sessions ?? [];
    expect(parsed[0].geo_country).toBe('DE');
    expect(parsed[1].geo_country).toBeNull();
  });

  it('parses rows that OMIT geo_country entirely — deploy skew must not fail the whole list', () => {
    // The wire payload above predates the geo join: the key is ABSENT (not
    // null) on every row. A mid-deploy response from an older backend must
    // still yield the full list rather than dropping every session.
    const payload = listPayload();
    expect('geo_country' in payload.details.sessions[0]).toBe(false);

    const result = colonelSessionsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details?.sessions).toHaveLength(2);
    expect(result.data.details?.sessions[0].geo_country).toBeUndefined();
  });

  it('rejects a raw session id under session_handle — the security tripwire', () => {
    // A backend regression that put the bearer sid back on the wire must fail
    // parsing here (the handle regex is 32 lowercase hex), not render in the UI.
    const payload = listPayload();
    (payload.details.sessions[0] as unknown as Record<string, unknown>).session_handle = RAW_SID;
    expect(colonelSessionsResponseSchema.safeParse(payload).success).toBe(false);
  });

  it('strips session_id / key if a backend still emits them', () => {
    const payload = listPayload();
    const row = payload.details.sessions[0] as unknown as Record<string, unknown>;
    row.session_id = RAW_SID;
    row.key = `session:${RAW_SID}`;

    const result = colonelSessionsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    const parsed = result.data.details?.sessions[0] as unknown as Record<string, unknown>;
    expect(parsed.session_id).toBeUndefined();
    expect(parsed.key).toBeUndefined();
  });

  it('rejects a row missing the required authenticated flag (contract drift)', () => {
    const payload = listPayload() as unknown as {
      details: { sessions: Array<{ authenticated?: boolean }> };
    };
    delete payload.details.sessions[0].authenticated;
    expect(colonelSessionsResponseSchema.safeParse(payload).success).toBe(false);
  });

  // #4328: the acting colonel's own row, so the console can disable its revoke.
  it('parses current_session_handle as a handle or a null', () => {
    const payload = listPayload() as unknown as {
      details: { current_session_handle?: string | null };
    };
    payload.details.current_session_handle = HANDLE_B;
    let result = colonelSessionsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.details?.current_session_handle).toBe(HANDLE_B);
    }

    payload.details.current_session_handle = null;
    result = colonelSessionsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.details?.current_session_handle).toBeNull();
    }
  });

  it('parses a listing that OMITS current_session_handle (deploy skew)', () => {
    const payload = listPayload();
    expect('current_session_handle' in payload.details).toBe(false);
    expect(colonelSessionsResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('rejects a raw session id under current_session_handle', () => {
    // The acting colonel's OWN sid is still a bearer credential: the same
    // tripwire has to cover it.
    const payload = listPayload() as unknown as {
      details: { current_session_handle?: string | null };
    };
    payload.details.current_session_handle = RAW_SID;
    expect(colonelSessionsResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('colonelSessionDetailResponseSchema (GetSessionDetail)', () => {
  function detailPayload() {
    return {
      shrimp: '',
      record: {
        session_handle: HANDLE,
        ttl: 3600,
        authenticated: true,
        email: 'alice@example.com',
        external_id: 'ext_1',
        account_id: 42,
        role: 'customer',
        locale: 'en',
        ip_address: '203.0.113.7',
        user_agent: 'Mozilla/5.0',
        org_context: 'org_ext_1',
        authenticated_at: 1700000000,
        authenticated_by: 'password',
        active_session_id: 'as_1',
      },
      details: {
        // csrf is stripped SERVER-SIDE now (#4330); the open record still
        // tolerates whatever session keys remain.
        data: { authenticated: true, email: 'alice@example.com' },
        scan_capped: false,
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

  it('accepts a detail payload that omits scan_capped (older backend)', () => {
    const payload = detailPayload();
    delete (payload.details as { scan_capped?: boolean }).scan_capped;
    expect(colonelSessionDetailResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('rejects a raw session id under record.session_handle', () => {
    const payload = detailPayload();
    payload.record.session_handle = RAW_SID;
    expect(colonelSessionDetailResponseSchema.safeParse(payload).success).toBe(false);
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
      record: { session_handle: HANDLE, deleted: true },
      details: { message: 'Session revoked successfully' },
    };
    const result = colonelSessionDeleteResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.deleted).toBe(true);
  });

  it('rejects an ack missing details.message', () => {
    const payload = {
      record: { session_handle: HANDLE, deleted: true },
      details: {},
    };
    expect(colonelSessionDeleteResponseSchema.safeParse(payload).success).toBe(false);
  });
});
