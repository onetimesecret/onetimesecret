// src/tests/apps/admin/customerDetailSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelUserDetailResponseSchema,
  colonelUserMutationResponseSchema,
} from '@/schemas/api/internal/responses/colonel';
import { responseSchemas } from '@/schemas/api/internal/responses/registry';

/**
 * Zod tripwire (CONTRACT 4). These payloads are shaped exactly as the Slice-2
 * logic classes emit them (verified against get_user_details.rb / set_user_role.rb
 * / set_user_verification.rb / purge_user.rb — timestamps as Unix-epoch numbers,
 * emails obscured, counters coerced to Integer). If the backend response drifts,
 * these fail rather than the UI silently breaking.
 */

// GetUserDetails `success_data`, on the wire (numbers for date fields).
function detailPayload() {
  return {
    shrimp: '',
    record: {
      extid: 'ur275l5nldar1ezxx8gdfi8oowy',
      email: 'ty***@e***.com',
      role: 'customer',
      verified: false,
      created: 1783378464.3955157, // fractional epoch seconds — real shape
      updated: 1783378464.400407,
      last_login: 1783378464,
      planid: 'basic',
      locale: '',
    },
    details: {
      secrets: {
        count: 1,
        items: [
          {
            secret_id: 'sec1',
            shortid: 'sh1',
            state: 'new',
            created: 1783378400,
            expiration: 1783382000,
          },
        ],
      },
      receipts: {
        count: 1,
        items: [{ receipt_id: 'rec1', shortid: 'rh1', state: 'viewed', created: 1783378401 }],
      },
      organizations: [
        { organization_id: 'org1', extid: 'og_abc', display_name: 'Acme', is_default: true },
      ],
      stats: { secrets_created: 5, secrets_shared: 2, emails_sent: 3 },
    },
  };
}

describe('colonelUserDetailResponseSchema (GetUserDetails)', () => {
  it('parses the real detail payload and transforms timestamps to Date', () => {
    const result = colonelUserDetailResponseSchema.safeParse(detailPayload());
    expect(result.success).toBe(true);
    if (!result.success) return;

    expect(result.data.record.created).toBeInstanceOf(Date);
    expect(result.data.record.updated).toBeInstanceOf(Date);
    expect(result.data.record.last_login).toBeInstanceOf(Date);
    expect(result.data.details?.secrets.items[0].created).toBeInstanceOf(Date);
    expect(result.data.details?.secrets.items[0].expiration).toBeInstanceOf(Date);
    expect(result.data.details?.stats.emails_sent).toBe(3);
  });

  it('accepts null last_login / expiration and null planid', () => {
    const payload = detailPayload();
    payload.record.last_login = null as unknown as number;
    payload.record.planid = null as unknown as string;
    payload.details.secrets.items[0].expiration = null as unknown as number;

    const result = colonelUserDetailResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.last_login).toBeNull();
    expect(result.data.record.planid).toBeNull();
    expect(result.data.details?.secrets.items[0].expiration).toBeNull();
  });

  it('rejects a payload whose secrets.count is missing (contract drift)', () => {
    const payload = detailPayload() as unknown as { details: { secrets: { count?: number } } };
    delete payload.details.secrets.count;
    expect(colonelUserDetailResponseSchema.safeParse(payload).success).toBe(false);
  });

  it('is registered under a stable registry key', () => {
    expect(responseSchemas.colonelUserDetail).toBe(colonelUserDetailResponseSchema);
  });
});

describe('colonelUserMutationResponseSchema (shared ack)', () => {
  it('validates the set-role ack', () => {
    const payload = {
      shrimp: '',
      record: {
        user_id: '019f-objid',
        extid: 'ur_abc',
        email: 'a***@e***.com',
        old_role: 'customer',
        new_role: 'admin',
        updated: 1783378464.4,
      },
      details: { changed: true, message: 'User role updated successfully' },
    };
    expect(colonelUserMutationResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('validates the verify / unverify ack', () => {
    const payload = {
      shrimp: '',
      record: {
        user_id: '019f-objid',
        extid: 'ur_abc',
        email: 'a***@e***.com',
        verified: true,
        updated: 1783378464,
      },
      details: { changed: true, message: 'User verified' },
    };
    expect(colonelUserMutationResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('validates the purge ack (no email/updated/changed)', () => {
    const payload = {
      shrimp: '',
      record: { deleted: true, user_id: '019f-objid', extid: 'ur_abc' },
      details: { message: 'User purged successfully' },
    };
    const result = colonelUserMutationResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.deleted).toBe(true);
  });

  it('rejects an ack missing the required details.message', () => {
    const payload = {
      record: { user_id: 'x', extid: 'ur_abc' },
      details: { changed: true },
    };
    expect(colonelUserMutationResponseSchema.safeParse(payload).success).toBe(false);
  });

  it('is registered under a stable registry key', () => {
    expect(responseSchemas.colonelUserMutation).toBe(colonelUserMutationResponseSchema);
  });
});
