// src/tests/apps/admin/bannedIpSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  bannedIPsResponseSchema,
  colonelBanIpResponseSchema,
  colonelUnbanIpResponseSchema,
} from '@/schemas/api/internal/responses/colonel-bannedips';

/**
 * Zod tripwire (CONTRACT 3) for the BannedIPs screen (#33). The two NEW ack
 * payloads are shaped exactly as the live logic classes emit them — verified
 * against apps/api/colonel/logic/colonel/ban_ip.rb and unban_ip.rb (which now
 * delegate to Onetime::Operations::BanIP / UnbanIP). The reused LIST schema is
 * re-exported from this per-resource module and is exercised too, so a backend
 * drift fails here rather than silently breaking the screen.
 */

describe('bannedIPsResponseSchema (ListBannedIPs — reused)', () => {
  it('parses the list read-out and keeps banned_at a number', () => {
    const payload = {
      shrimp: '',
      record: {},
      details: {
        current_ip: '203.0.113.9',
        banned_ips: [
          {
            id: 'banned_ip_objid',
            ip_address: '203.0.113.4',
            reason: 'abuse',
            banned_by: 'objid_colonel',
            banned_at: 1783378400,
          },
        ],
        total_count: 1,
      },
    };
    const result = bannedIPsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details?.banned_ips[0].banned_at).toBe(1783378400);
    expect(result.data.details?.current_ip).toBe('203.0.113.9');
  });

  it('defaults current_ip to "unknown" when omitted', () => {
    const payload = {
      shrimp: '',
      record: {},
      details: { banned_ips: [], total_count: 0 },
    };
    const result = bannedIPsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details?.current_ip).toBe('unknown');
  });

  it('accepts a ban record with null reason + banned_by (anonymous/CLI ban)', () => {
    const payload = {
      shrimp: '',
      record: {},
      details: {
        current_ip: '203.0.113.9',
        banned_ips: [
          { id: 'x', ip_address: '203.0.113.0/24', reason: null, banned_by: null, banned_at: 1 },
        ],
        total_count: 1,
      },
    };
    expect(bannedIPsResponseSchema.safeParse(payload).success).toBe(true);
  });
});

describe('colonelBanIpResponseSchema (BanIP ack)', () => {
  it('validates the ban ack', () => {
    const payload = {
      shrimp: '',
      record: {
        id: 'banned_ip_objid',
        ip_address: '203.0.113.4',
        reason: 'credential stuffing',
        banned_by: 'objid_colonel',
        banned_at: 1783378400,
      },
      details: { message: 'IP address banned successfully' },
    };
    const result = colonelBanIpResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.banned_at).toBe(1783378400);
    expect(result.data.record.ip_address).toBe('203.0.113.4');
  });

  it('accepts a null reason + banned_by (permanent ban with no reason)', () => {
    const payload = {
      shrimp: '',
      record: { id: 'x', ip_address: '203.0.113.4', reason: null, banned_by: null, banned_at: 1 },
      details: { message: 'IP address banned successfully' },
    };
    expect(colonelBanIpResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('rejects a ban ack missing ip_address (contract drift)', () => {
    const payload = {
      record: { id: 'x', reason: null, banned_by: null, banned_at: 1 },
      details: { message: 'ok' },
    };
    expect(colonelBanIpResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('colonelUnbanIpResponseSchema (UnbanIP ack)', () => {
  it('validates the unban ack', () => {
    const payload = {
      shrimp: '',
      record: { ip_address: '203.0.113.4', unbanned: true },
      details: { message: 'IP address unbanned successfully' },
    };
    const result = colonelUnbanIpResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.unbanned).toBe(true);
  });

  it('rejects an unban ack missing details.message', () => {
    const payload = {
      record: { ip_address: '203.0.113.4', unbanned: true },
      details: {},
    };
    expect(colonelUnbanIpResponseSchema.safeParse(payload).success).toBe(false);
  });
});
