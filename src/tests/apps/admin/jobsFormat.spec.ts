// src/tests/apps/admin/jobsFormat.spec.ts

import { describe, expect, it } from 'vitest';

import {
  dlqDeepScanCommand,
  runStatusBadgeClass,
  shellArg,
} from '@/apps/admin/components/jobs/jobsFormat';
import type { JobRunStatus } from '@/schemas/api/internal/responses/colonel-jobs';

/**
 * Last-run badge tones. A `partial` run (finished, some records failed) reads
 * amber like `error`; `skipped` and `never` stay neutral.
 */
describe('jobsFormat — run status badges', () => {
  it.each<[JobRunStatus, string]>([
    ['error', 'bg-amber-100'],
    ['partial', 'bg-amber-100'],
    ['success', 'bg-green-100'],
    ['running', 'bg-brand-100'],
    ['skipped', 'bg-gray-100'],
    ['never', 'bg-gray-100'],
  ])('tones %s', (status, tone) => {
    expect(runStatusBadgeClass(status)).toContain(tone);
  });
});

/**
 * The CLI hint the Jobs screen shows after a truncated DLQ scan (#4343 R1-1).
 * A message id is whatever the publisher set, so it is quoted for the shell.
 */
describe('jobsFormat — CLI hints', () => {
  it.each([
    ['billing.event', 'billing.event'],
    ['a1b2-c3d4_e5', 'a1b2-c3d4_e5'],
    ['urn:uuid:1234@host/x+y=z', 'urn:uuid:1234@host/x+y=z'],
  ])('leaves a shell-safe argument bare: %s', (value, expected) => {
    expect(shellArg(value)).toBe(expected);
  });

  it.each([
    ['two words', `'two words'`],
    ['$(rm -rf /)', `'$(rm -rf /)'`],
    [`it's`, `'it'\\''s'`],
    ['', `''`],
  ])('single-quotes anything else: %s', (value, expected) => {
    expect(shellArg(value)).toBe(expected);
  });

  it('builds the deeper show command with the scan bound left to the operator', () => {
    expect(dlqDeepScanCommand('email.message', 'm 1')).toBe(
      `bin/ots queue dlq show email.message --id 'm 1' --max-scan N`
    );
  });
});
