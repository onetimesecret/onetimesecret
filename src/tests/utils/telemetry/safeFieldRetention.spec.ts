// src/tests/utils/telemetry/safeFieldRetention.spec.ts
//
// Pins the ONE guarantee `safeFieldRegistry` exists to provide, against the
// REAL Colonel schema rather than a synthetic one.
//
// The docblock on `isSafeFieldEnrolled` used to justify the retention tier with
// an ordinal — "it is the 12th key in declaration order". Executed against
// `colonelOrganizationDetailRecordSchema`, `subscription_period_end` is the
// 21st of 24 fields. The substance held (it sits well past the 10-row cap) but
// the number did not, and it will drift again the next time the schema grows.
//
// So the guarantee is asserted by execution instead: drift EVERY field of the
// live schema at once — the mixed-version rollout the branch exists for — and
// require the enrolled row to survive truncation on both emitted surfaces.
// No ordinal in a comment has to be right for that to hold.

import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { colonelOrganizationDetailRecordSchema } from '@/schemas/api/internal/responses/colonel-organizations';
import {
  MAX_PROJECTED_ISSUES,
  projectSchemaIssues,
} from '@/utils/telemetry/schemaIssueProjection';
import { enrolledSafeFieldKeys } from '@/utils/telemetry/safeFieldRegistry';

const SCHEMA_NAME = 'ColonelOrganizationDetailResponse';
const ENROLLED_PATH = 'record.subscription_period_end';

/** Field names of the live record schema, in declaration order. */
function recordFieldNames(): string[] {
  const shape = (colonelOrganizationDetailRecordSchema as unknown as { shape: Record<string, unknown> })
    .shape;
  return Object.keys(shape);
}

/** The whole record drifting at once, wrapped as the response envelope is. */
function fullyDriftedResponse(): { record: Record<string, unknown> } {
  const record: Record<string, unknown> = {};
  for (const name of recordFieldNames()) record[name] = { unexpected: 'object' };
  return { record };
}

describe('the enrolled Colonel field survives a whole-response drift', () => {
  it('the registry holds exactly the one reviewed entry', () => {
    expect(enrolledSafeFieldKeys()).toEqual([`${SCHEMA_NAME}|${ENROLLED_PATH}`]);
  });

  it('the enrolled field really does sit past the row cap in declaration order', () => {
    const names = recordFieldNames();
    const ordinal = names.indexOf('subscription_period_end') + 1;

    expect(ordinal).toBeGreaterThan(0);
    // The claim that matters, stated without hard-coding an ordinal that drifts.
    expect(ordinal).toBeGreaterThan(MAX_PROJECTED_ISSUES);
  });

  it('retains the enrolled row even though declaration order would evict it', () => {
    const data = fullyDriftedResponse();
    const schema = z.object({ record: colonelOrganizationDetailRecordSchema });
    const result = schema.safeParse(data);
    expect(result.success).toBe(false);

    const projection = projectSchemaIssues(result.error!, data, SCHEMA_NAME);

    expect(projection.truncated).toBe(true);
    expect(projection.rows.map((row) => row.path)).toContain(ENROLLED_PATH);
    // And it heads the searchable tag, so it survives the consumer's 200-char cut.
    expect(projection.paths[0]).toBe(ENROLLED_PATH);
  });

  it('carries its shape descriptors, and no value, on the retained row', () => {
    // A representation the widened union still refuses, which is the only kind
    // that reaches this row now — see the second describe block.
    const data = fullyDriftedResponse();
    const schema = z.object({ record: colonelOrganizationDetailRecordSchema });
    const projection = projectSchemaIssues(schema.safeParse(data).error!, data, SCHEMA_NAME);
    const row = projection.rows.find((candidate) => candidate.path === ENROLLED_PATH);

    expect(row).toBeDefined();
    expect(row).toMatchObject({
      received_type: 'object',
      numeric_kind: 'non_numeric',
      timestamp_format: 'not_applicable',
    });
  });

  it('a NUMERIC epoch produces no row for the field at all any more', () => {
    // The motivating bug, replayed against the schema as it stands. It parses,
    // so the enrolled descriptors never fire for it. safeFieldRegistry's header
    // says so; this is that sentence, executed.
    const data = fullyDriftedResponse();
    data.record.subscription_period_end = 1772940425;
    const schema = z.object({ record: colonelOrganizationDetailRecordSchema });
    const projection = projectSchemaIssues(schema.safeParse(data).error!, data, SCHEMA_NAME);

    expect(projection.rows.map((row) => row.path)).not.toContain(ENROLLED_PATH);
    expect(JSON.stringify(projection)).not.toContain('1772940425');
  });

  it('an unenrolled sibling gets no descriptors at all', () => {
    const data = fullyDriftedResponse();
    const schema = z.object({ record: colonelOrganizationDetailRecordSchema });
    const projection = projectSchemaIssues(schema.safeParse(data).error!, data, SCHEMA_NAME);
    const sibling = projection.rows.find((row) => row.path === 'record.owner_email');

    if (sibling) {
      expect(Object.keys(sibling).sort()).toEqual(['code', 'expected', 'path', 'received']);
    }
  });
});

describe('the widened schema no longer reproduces the original epoch failure', () => {
  // safeFieldRegistry's header describes the pre-fix wire format. This pins the
  // present tense so that history can never be mistaken for current behaviour.
  const base: Record<string, unknown> = {
    org_id: 'o', extid: 'e', display_name: null, description: null, is_default: false,
    archived: false, archived_at: null, archived_comment: null, contact_email: null,
    owner_id: null, owner_email: null, billing_email: null, member_count: 0, domain_count: 0,
    created: null, updated: null, planid: null, stripe_customer_id: null,
    stripe_subscription_id: null, subscription_status: null, subscription_period_end: null,
    billing_email_present: false, sync_status: 'ok', sync_status_reason: null,
  };

  it('accepts BOTH the Integer epoch and the coerced string', () => {
    expect(
      colonelOrganizationDetailRecordSchema.safeParse({ ...base, subscription_period_end: 1772940425 })
        .success
    ).toBe(true);
    expect(
      colonelOrganizationDetailRecordSchema.safeParse({
        ...base,
        subscription_period_end: '1772940425',
      }).success
    ).toBe(true);
  });
});
