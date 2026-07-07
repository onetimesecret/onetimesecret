// src/tests/apps/admin/domainToolboxSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelDomainsOrphanedResponseSchema,
  colonelDomainProbeResponseSchema,
  colonelDomainRepairResponseSchema,
  colonelDomainTransferResponseSchema,
} from '@/schemas/api/internal/responses/colonel-domaintoolbox';

/**
 * Zod tripwire (CONTRACT 3) for the four NEW Domain-Toolbox contracts (ticket
 * #43). Payloads are shaped exactly as the live logic classes emit them —
 * verified against apps/api/colonel/logic/colonel/{list_orphaned_domains,
 * probe_domain,repair_domain,transfer_domain}.rb, thin adapters over
 * Onetime::Operations::Domains::*. If a backend response drifts, these fail
 * rather than the screen silently breaking.
 */

describe('colonelDomainsOrphanedResponseSchema', () => {
  it('parses an orphaned-scan page (epoch created → Date)', () => {
    const parsed = colonelDomainsOrphanedResponseSchema.parse({
      shrimp: '',
      record: {},
      details: {
        domains: [
          {
            domain_id: 'cd_1',
            extid: 'cd_ext_1',
            display_domain: 'orphan.example.com',
            verification_state: 'pending',
            verified: false,
            created: 1700000000,
          },
        ],
        pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
      },
    });
    expect(parsed.details?.domains[0].created).toBeInstanceOf(Date);
    expect(parsed.details?.domains[0].extid).toBe('cd_ext_1');
  });
});

describe('colonelDomainProbeResponseSchema', () => {
  it('parses a healthy probe with SSL cert details', () => {
    const parsed = colonelDomainProbeResponseSchema.parse({
      shrimp: '',
      record: { extid: 'cd_ext_1', display_domain: 'example.com' },
      details: {
        timestamp: '2026-07-07T00:00:00Z',
        domain: 'example.com',
        url: 'https://example.com',
        http: { status_code: 200, status_message: 'OK', success: true },
        ssl: {
          valid: true,
          subject: 'CN=example.com',
          issuer: 'CN=CA',
          not_before: '2026-01-01T00:00:00Z',
          not_after: '2026-12-31T00:00:00Z',
          days_until_expiry: 100,
          expired: false,
          not_yet_valid: false,
        },
        health: 'healthy',
      },
    });
    expect(parsed.details?.health).toBe('healthy');
    expect(parsed.details?.http.success).toBe(true);
  });

  it('parses an error probe with no SSL arm (connection refused)', () => {
    const parsed = colonelDomainProbeResponseSchema.parse({
      shrimp: '',
      record: { extid: 'cd_ext_1', display_domain: 'down.example.com' },
      details: {
        timestamp: '2026-07-07T00:00:00Z',
        domain: 'down.example.com',
        url: 'https://down.example.com',
        http: { error: 'Connection Refused', message: 'ECONNREFUSED' },
        health: 'connection_refused',
      },
    });
    expect(parsed.details?.ssl).toBeUndefined();
    expect(parsed.details?.http.error).toBe('Connection Refused');
  });
});

describe('colonelDomainRepairResponseSchema', () => {
  it('parses a dry-run plan with issues', () => {
    const parsed = colonelDomainRepairResponseSchema.parse({
      shrimp: '',
      record: { domain_id: 'cd_1', extid: 'cd_ext_1', display_domain: 'x.example.com' },
      details: {
        status: 'planned',
        dry_run: true,
        issues: ["org_id is on_abc but not in organization's domains collection"],
        repairs_applied: [],
      },
    });
    expect(parsed.details?.status).toBe('planned');
    expect(parsed.details?.issues).toHaveLength(1);
    expect(parsed.details?.repairs_applied).toHaveLength(0);
  });
});

describe('colonelDomainTransferResponseSchema', () => {
  it('parses a transfer plan with a nullable from-org name and orphaned id', () => {
    const parsed = colonelDomainTransferResponseSchema.parse({
      shrimp: '',
      record: { domain_id: 'cd_1', extid: 'cd_ext_1', display_domain: 'x.example.com' },
      details: {
        status: 'planned',
        dry_run: true,
        from_org_id: '',
        from_org_name: null,
        to_org_id: 'on_dest',
        to_org_name: 'Dest Org',
      },
    });
    expect(parsed.details?.from_org_id).toBe('');
    expect(parsed.details?.from_org_name).toBeNull();
    expect(parsed.details?.to_org_name).toBe('Dest Org');
  });
});
