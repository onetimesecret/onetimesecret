// src/tests/apps/admin/backupStatusSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import { backupStatusResponseSchema } from '@/schemas/api/internal/responses/colonel-system';

function record(overrides: Record<string, unknown> = {}) {
  return {
    event: 'ok',
    ts: 1_700_000_000,
    host: 'eu-db-01',
    unit: 'ots-backup-pg.service',
    job: 'pg',
    file: '/var/backups/onetimesecret/pg.sql.gz',
    bytes: '1048576',
    sha256: 'a'.repeat(64),
    mode: '',
    removed: '',
    candidates: '',
    duration_secs: '15',
    error: '',
    version: '0.2.3',
    scheduled: 'enabled',
    ...overrides,
  };
}

function payload() {
  return {
    shrimp: '',
    record: {},
    details: {
      timestamp: 1_700_000_100,
      jobs: [
        { job: 'pg', configured: true, latest: record(), last_ok: record() },
        { job: 'valkey', configured: false, latest: null, last_ok: null },
        { job: 'prune', configured: false, latest: null, last_ok: null },
        { job: 'ship', configured: false, latest: null, last_ok: null },
      ],
    },
  };
}

describe('backup status schema (#4276)', () => {
  it('accepts configured and not-configured recognized jobs', () => {
    const parsed = backupStatusResponseSchema.safeParse(payload());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.details?.jobs[0].last_ok?.file).toContain('pg.sql.gz');
      expect(parsed.data.details?.jobs[1]).toMatchObject({ job: 'valkey', configured: false });
    }
  });

  it('accepts malformed external values normalized by the backend to null', () => {
    const malformed = payload();
    malformed.details.jobs[0].latest = record({ event: null, ts: null, error: null });
    malformed.details.jobs[0].last_ok = null;

    expect(backupStatusResponseSchema.safeParse(malformed).success).toBe(true);
  });

  it('rejects a job row without the configured discovery result', () => {
    const invalid = payload();
    // @ts-expect-error — deliberate contract drift.
    delete invalid.details.jobs[0].configured;

    expect(backupStatusResponseSchema.safeParse(invalid).success).toBe(false);
  });
});
