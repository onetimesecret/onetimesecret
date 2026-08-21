// src/tests/utils/telemetry/schemaIssueProjection.spec.ts
//
// PASS-THREE REGRESSION SUITE for the schema-issue projection.
//
// Every case below was reproduced against the tree before it was fixed, using
// the inputs written here verbatim. The two failure modes are treated as equally
// serious, because they are:
//
//   UNDER-SCRUBBING  — a payload-derived value reaching an UNSCRUBBED Sentry
//                      extras field. `createBeforeSendHandler` never touches
//                      `event.extra`, so the projection is the only control.
//   OVER-SCRUBBING   — a schema-authored field name, type, bound or enum being
//                      redacted or dropped. That is what made #3424 take three
//                      fixes, and it is a regression, not a safe default.
//
// The end-to-end leak suite is
// src/tests/plugins/core/diagnostics/telemetryBoundary.spec.ts; this file pins
// the unit-level behaviour that suite depends on.

import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  MAX_PROJECTED_ISSUES,
  MAX_PROJECTED_PATHS,
  projectSchemaIssues,
  REDACTED_SEGMENT,
  ROOT_PATH,
  typeNameOf,
} from '@/utils/telemetry/schemaIssueProjection';
import {
  parameterizeApiPath,
  resetApiRouteContext,
  sanitizeApiRoute,
  setCurrentApiRoute,
  resolveApiRoute,
} from '@/utils/telemetry/apiRouteContext';
import { enrolledSafeFieldKeys, isSafeFieldEnrolled } from '@/utils/telemetry/safeFieldRegistry';

/** Projects `data` through `schema` and returns the projection. */
function project(schema: z.ZodType, data: unknown, context?: string, limit?: number) {
  const result = schema.safeParse(data);
  expect(result.success).toBe(false);
  return projectSchemaIssues(result.error!, data, context, limit);
}

/** The whole projection as one string, for absence assertions. */
function wire(projection: unknown): string {
  return JSON.stringify(projection);
}

// ===========================================================================
// DEFECT 1 — payload-derived path segments reaching unscrubbed extras
// ===========================================================================
describe('DEFECT 1 — path segments that came off the wire', () => {
  // A Zod path segment is USUALLY a schema-authored field name. For a
  // `z.record()` it is the PAYLOAD KEY, and record-typed schemas are parsed
  // through gracefulParse today (colonel-sessions.ts `data: z.record`,
  // colonel.ts, colonel-billing.ts, the Stripe `metadata` records in
  // account/stripe-types.ts, errors/types.ts).
  const recordSchema = z.record(z.string(), z.number());

  it('redacts an email address used as a record key', () => {
    const projection = project(recordSchema, { 'alice@example.com': 'nope' });

    expect(projection.rows[0].path).toBe(REDACTED_SEGMENT);
    expect(wire(projection)).not.toContain('alice@example.com');
    expect(wire(projection)).not.toContain('alice');
  });

  it('redacts a prefixed tenant id used as a record key', () => {
    const projection = project(recordSchema, { org_9f3a2b1c8d7e6f50: 'nope' });

    expect(projection.rows[0].path).toBe(REDACTED_SEGMENT);
    expect(wire(projection)).not.toContain('org_9f3a2b1c8d7e6f50');
  });

  it('redacts a credential used as a record key on an invalid_key issue', () => {
    // `invalid_key` is the other shape: the segment is the key that failed the
    // KEY schema, so it is payload-derived by definition.
    const projection = project(z.record(z.uuid(), z.number()), {
      sk_live_51H8xQzABCDEF: 1,
    });

    expect(projection.rows[0].code).toBe('invalid_key');
    expect(projection.rows[0].path).toBe(REDACTED_SEGMENT);
    expect(wire(projection)).not.toContain('sk_live_');
  });

  it('scrubs BOTH surfaces, not just the tag — rows and paths alike', () => {
    // The consumer scrubbed `projection.paths` (the tag) while shipping
    // `projection.rows` to extras untouched. The mitigation had been applied to
    // the cheap half only.
    const projection = project(recordSchema, { 'alice@example.com': 'nope' });

    expect(projection.paths).toEqual([REDACTED_SEGMENT]);
    expect(projection.rows.map((row) => row.path)).toEqual([REDACTED_SEGMENT]);
  });

  it('redacts ONLY the offending segment, keeping the schema-authored parents', () => {
    // Flattening a whole path to one token would destroy the #3424 contract:
    // the readable parent is most of the diagnostic value.
    const schema = z.object({ record: z.object({ tags: z.record(z.string(), z.number()) }) });

    const projection = project(schema, {
      record: { tags: { 'alice@example.com': 'nope' } },
    });

    expect(projection.rows[0].path).toBe(`record.tags.${REDACTED_SEGMENT}`);
  });

  it('does NOT redact ordinary schema-authored field names', () => {
    // Over-scrubbing is the symmetric defect. These are real field names from
    // src/schemas, several of them digit-bearing.
    const shape: Record<string, z.ZodTypeAny> = {
      subscription_period_end: z.string(),
      display_name_i18n_key: z.string(),
      max_24_hour_send: z.string(),
      sent_last_24_hours: z.string(),
      utf8_sanitizer: z.string(),
      d9s_enabled: z.string(),
      smtp2go: z.string(),
      last4: z.string(),
      stripe_customer_id: z.string(),
    };
    const payload = Object.fromEntries(Object.keys(shape).map((key) => [key, 1]));

    const projection = project(z.object(shape), payload, 'Ctx', 50);

    expect(projection.paths.sort()).toEqual(Object.keys(shape).sort());
    expect(wire(projection)).not.toContain(REDACTED_SEGMENT);
  });

  it('keeps array indices readable', () => {
    const schema = z.object({ items: z.array(z.object({ v: z.string() })) });

    const projection = project(schema, { items: [{ v: 'ok' }, { v: 1 }] });

    expect(projection.rows[0].path).toBe('items.1.v');
  });

  it('uses (root) for an empty path', () => {
    const projection = project(z.object({ a: z.string() }), 'not-an-object');

    expect(projection.rows[0].path).toBe(ROOT_PATH);
  });
});

// ===========================================================================
// DEFECT 2 — the caller-supplied apiRoute was scrubbed but not parameterized
// ===========================================================================
describe('DEFECT 2 — sanitizeApiRoute is the single route chokepoint', () => {
  it('parameterizes a resolved URL handed to it, contract violation or not', () => {
    // The option's TSDoc said "NEVER pass a resolved URL — it is
    // re-parameterized"; only the resolver path actually did that.
    expect(sanitizeApiRoute('/api/colonel/organizations/org_9f3a2b1c8d7e6f50')).toBe(
      '/api/colonel/organizations/:org_id'
    );
  });

  it('leaves an already-parameterized route exactly as given', () => {
    expect(sanitizeApiRoute('/api/v3/receipts/:key')).toBe('/api/v3/receipts/:key');
  });

  it('returns undefined for anything that is not a route', () => {
    expect(sanitizeApiRoute(undefined)).toBeUndefined();
    expect(sanitizeApiRoute('')).toBeUndefined();
  });
});

// ===========================================================================
// DEFECT 3 — apiRoute parameterization missed IPs and percent-encoded PII
// ===========================================================================
describe('DEFECT 3 — identifier segments that are not [0-9a-zA-Z_-]', () => {
  // Every one of these passed through VERBATIM before the fix: a dot, an `@` or
  // a `%` made a segment fail every shape branch at once, because they all
  // required `^[0-9a-zA-Z_-]+$`.
  it.each([
    // AdminBannedIps.vue:123 issues this DELETE and gracefulParses the reply.
    ['/api/colonel/banned-ips/203.0.113.5', '/api/colonel/banned-ips/:id'],
    ['/api/colonel/banned-ips/2001%3Adb8%3A%3A42', '/api/colonel/banned-ips/:id'],
    ['/api/colonel/users/alice%40example.com', '/api/colonel/users/:user_id'],
    ['/api/domains/mail.acmecorp.example/brand', '/api/domains/:domain_id/brand'],
  ])('parameterizes %s', (input, expected) => {
    expect(parameterizeApiPath(input)).toBe(expected);
  });

  it('keeps an end-user IP out of the resolved route entirely', () => {
    // An end-user IP in extras is exactly what actorIdentity pins
    // `ip_address: null` to prevent.
    resetApiRouteContext();
    setCurrentApiRoute('/api/colonel/banned-ips/203.0.113.5');

    expect(resolveApiRoute()).toBe('/api/colonel/banned-ips/:id');
    expect(resolveApiRoute()).not.toContain('203.0.113.5');
    resetApiRouteContext();
  });

  it('still leaves literal route words alone', () => {
    expect(parameterizeApiPath('/api/v3/status')).toBe('/api/v3/status');
    expect(parameterizeApiPath('/api/colonel/banned-ips')).toBe('/api/colonel/banned-ips');
    expect(parameterizeApiPath('/api/organizations/:org_id/secret-activity')).toBe(
      '/api/organizations/:org_id/secret-activity'
    );
  });
});

// ===========================================================================
// DEFECT 4 — truncation was first-N in Zod DECLARATION order
// ===========================================================================
describe('DEFECT 4 — truncation keeps the row that matters', () => {
  const ENROLLED_SCHEMA = 'ColonelOrganizationDetailResponse';

  /** A Colonel record with 15 broken fields; the enrolled one is field #12. */
  function colonelDrift() {
    const inner: Record<string, z.ZodTypeAny> = {};
    const payload: Record<string, unknown> = {};
    const names = [
      'identifier',
      'name',
      'display_domain',
      'owner_ref',
      'plan_id',
      'member_count',
      'domain_count',
      'created',
      'updated',
      'stripe_customer_id',
      'stripe_subscription_id',
      'subscription_period_end',
      'billing_email',
      'seat_limit',
      'status',
    ];
    for (const name of names) {
      inner[name] = z.string();
      payload[name] = 1772940425;
    }
    return { schema: z.object({ record: z.object(inner) }), payload: { record: payload } };
  }

  it('retains the registry-enrolled field even when it is the 12th issue', () => {
    const { schema, payload } = colonelDrift();

    const projection = project(schema, payload, ENROLLED_SCHEMA);

    expect(projection.issueCount).toBe(15);
    expect(projection.truncated).toBe(true);
    expect(projection.rows.map((row) => row.path)).toContain(
      'record.subscription_period_end'
    );
  });

  it('keeps that field on the searchable schemaField path list too', () => {
    // "show me every event where record.subscription_period_end failed" used to
    // return ZERO HITS during exactly the mixed-version rollout this branch
    // exists for.
    const { schema, payload } = colonelDrift();

    const projection = project(schema, payload, ENROLLED_SCHEMA);

    expect(projection.paths).toContain('record.subscription_period_end');
    expect(projection.paths[0]).toBe('record.subscription_period_end');
  });

  it('still carries the registry descriptors on the retained row', () => {
    const { schema, payload } = colonelDrift();

    const projection = project(schema, payload, ENROLLED_SCHEMA);
    const row = projection.rows.find((r) => r.path === 'record.subscription_period_end')!;

    expect(row).toMatchObject({
      code: 'invalid_type',
      expected: 'string',
      received: 'number',
      numeric_kind: 'integer',
      timestamp_format: 'unix_seconds',
    });
  });

  it('prefers a distinct (path, code) pair over a repeat of one already kept', () => {
    // 12 array elements failing identically, then one genuinely different
    // field. Declaration order would have dropped the different one. Array
    // indices are collapsed for the distinctness key, so `items.0.v` counts as
    // representing `items.1.v` .. `items.11.v` — same failure, different index.
    const schema = z.object({
      items: z.array(z.object({ v: z.string() })),
      sync_status: z.number(),
    });
    const payload = {
      items: Array.from({ length: 12 }, () => ({ v: 1 })),
      sync_status: 'pending',
    };

    const projection = project(schema, payload, 'Ctx');

    expect(projection.rows.map((row) => row.path)).toContain('sync_status');
  });

  it('emits survivors back in declaration order', () => {
    const projection = project(
      z.object({ a: z.string(), b: z.string(), c: z.string() }),
      { a: 1, b: 2, c: 3 },
      'Ctx'
    );

    expect(projection.rows.map((row) => row.path)).toEqual(['a', 'b', 'c']);
  });

  it('gives the path list its own, larger cap than the row cap', () => {
    const shape: Record<string, z.ZodTypeAny> = {};
    const payload: Record<string, unknown> = {};
    for (let i = 0; i < MAX_PROJECTED_PATHS + 5; i += 1) {
      shape[`f${i}`] = z.string();
      payload[`f${i}`] = i;
    }

    const projection = project(z.object(shape), payload, 'Ctx');

    expect(projection.rows.filter((r) => r.code !== 'projection_truncated')).toHaveLength(
      MAX_PROJECTED_ISSUES
    );
    expect(projection.paths).toHaveLength(MAX_PROJECTED_PATHS);
    expect(MAX_PROJECTED_PATHS).toBeGreaterThan(MAX_PROJECTED_ISSUES);
  });
});

// ===========================================================================
// DEFECT 5 — invalid_value dropped the accepted set and never set `expected`
// ===========================================================================
describe('DEFECT 5 — the accepted literal set', () => {
  it('answers "what does the schema accept?" for enum drift', () => {
    // Reproduced: the row was only
    // {path:"sync_status", code:"invalid_value", received:"string"} — the
    // operator could not tell enum drift from a typo without opening source.
    const projection = project(
      z.object({ sync_status: z.enum(['ok', 'stale', 'error']) }),
      { sync_status: 'pending' },
      'Ctx'
    );

    expect(projection.rows[0]).toMatchObject({
      path: 'sync_status',
      code: 'invalid_value',
      expected: '"ok"|"stale"|"error"',
      received: 'string',
    });
  });

  it('never emits the rejected payload value alongside it', () => {
    const projection = project(
      z.object({ sync_status: z.enum(['ok', 'stale', 'error']) }),
      { sync_status: 'pending' },
      'Ctx'
    );

    expect(wire(projection)).not.toContain('pending');
  });

  it('handles a literal as a one-member set', () => {
    const projection = project(z.object({ kind: z.literal('receipt') }), { kind: 'secret' }, 'Ctx');

    expect(projection.rows[0].expected).toBe('"receipt"');
    expect(wire(projection)).not.toContain('secret');
  });

  it('FAILS CLOSED if an accepted value ever stops being schema-authored', () => {
    // The no-runtime-enum claim was re-verified for this tree, but a claim
    // about today's source is not a control. A hand-built issue standing in for
    // a future runtime-constructed enum must drop the whole field.
    const fake = {
      issues: [
        {
          code: 'invalid_value',
          path: ['mode'],
          values: ['ok', 'alice@example.com'],
          message: 'x',
        },
      ],
    } as unknown as z.ZodError;

    const projection = projectSchemaIssues(fake, { mode: 'x' }, 'Ctx');

    expect(projection.rows[0]).not.toHaveProperty('expected');
    expect(wire(projection)).not.toContain('alice@example.com');
  });

  it('refuses a non-primitive member rather than stringifying it', () => {
    const fake = {
      issues: [{ code: 'invalid_value', path: ['mode'], values: [{ a: 1 }], message: 'x' }],
    } as unknown as z.ZodError;

    const projection = projectSchemaIssues(fake, { mode: 'x' }, 'Ctx');

    expect(projection.rows[0]).not.toHaveProperty('expected');
    expect(wire(projection)).not.toContain('[object Object]');
  });
});

// ===========================================================================
// DEFECT 6 — format and bound constants were dropped wholesale
// ===========================================================================
describe('DEFECT 6 — schema-authored formats and bounds', () => {
  it('distinguishes a z.email() failure from a z.url() failure', () => {
    // Reproduced: these two were BYTE-IDENTICAL on the wire, both reading
    // {code:"invalid_format", received:"string"}.
    const emailProjection = project(z.object({ a: z.email() }), { a: 'nope' }, 'Ctx');
    const urlProjection = project(z.object({ a: z.url() }), { a: 'nope' }, 'Ctx');

    expect(emailProjection.rows[0].expected).toBe('email');
    expect(urlProjection.rows[0].expected).toBe('url');
    expect(emailProjection.rows[0]).not.toEqual(urlProjection.rows[0]);
  });

  it('names the violated bound for too_small', () => {
    const projection = project(z.object({ a: z.string().min(8) }), { a: 'nope' }, 'Ctx');

    expect(projection.rows[0]).toMatchObject({ code: 'too_small', expected: 'string >=8' });
  });

  it('names the violated bound for too_big', () => {
    const projection = project(z.object({ a: z.number().max(5) }), { a: 9 }, 'Ctx');

    expect(projection.rows[0]).toMatchObject({ code: 'too_big', expected: 'number <=5' });
  });

  it('never emits the payload value that violated the bound', () => {
    const projection = project(
      z.object({ a: z.string().min(8) }),
      { a: 'RAW-9f' },
      'Ctx'
    );

    expect(wire(projection)).not.toContain('RAW-9f');
  });

  it('keeps invalid_format.pattern DROPPED', () => {
    // A regex is authored, but it is verbose, adds little a format name does
    // not, and can encode more than its author intended.
    const projection = project(
      z.object({ a: z.string().regex(/^ab+c$/) }),
      { a: 'nope' },
      'Ctx'
    );

    expect(projection.rows[0].expected).toBe('regex');
    expect(wire(projection)).not.toContain('ab+c');
  });
});

// ===========================================================================
// DEFECT 7 — custom refinement identity was gone with no substitute
// ===========================================================================
describe('DEFECT 7 — custom issues get an identity, never a message', () => {
  it('reads an author-declared refinement id out of params', () => {
    const schema = z.string().superRefine((_v, ctx) => {
      ctx.addIssue({ code: 'custom', message: 'x', params: { id: 'pw_complexity' } });
    });

    const projection = project(schema, 'x', 'Ctx');

    expect(projection.rows[0]).toMatchObject({ code: 'custom', issueCode: 'pw_complexity' });
  });

  it('never emits params wholesale — the audit found one carrying a live key', () => {
    const schema = z.string().superRefine((_v, ctx) => {
      ctx.addIssue({
        code: 'custom',
        message: 'x',
        params: { id: 'pw_complexity', secret: 'sk_live_SUPER_SECRET' },
      });
    });

    const projection = project(schema, 'x', 'Ctx');

    expect(wire(projection)).not.toContain('sk_live_SUPER_SECRET');
    expect(wire(projection)).not.toContain('secret');
  });

  it('distinguishes two refinements at ONE path without shipping either message', () => {
    // A superRefine adding several issues at one path used to collapse to N
    // identical {path:"(root)", code:"custom"} rows, and `redactionSignals`
    // yields nothing for a static message — pure loss, zero privacy gain.
    const schema = z.object({ a: z.string() }).superRefine((_v, ctx) => {
      ctx.addIssue({ code: 'custom', message: 'must exceed 3 chars' });
      ctx.addIssue({ code: 'custom', message: 'must have a name' });
    });

    const projection = project(schema, { a: 'x' }, 'Ctx');
    const codes = projection.rows.map((row) => row.issueCode);

    expect(codes[0]).not.toBe(codes[1]);
    expect(codes.every((code) => String(code).startsWith('shape:'))).toBe(true);
    expect(wire(projection)).not.toContain('exceed');
    expect(wire(projection)).not.toContain('name');
  });

  it('derives the discriminator from message SHAPE, over a five-symbol alphabet', () => {
    const schema = z.object({
      a: z.string().refine((v) => v.length > 3, 'a must exceed 3 chars'),
    });

    const projection = project(schema, { a: 'x' }, 'Ctx');

    expect(projection.rows[0].issueCode).toBe('shape:aaa9a');
    expect(String(projection.rows[0].issueCode)).toMatch(/^shape:[a9xps]+$/);
  });

  it('is stable across events for the same refinement', () => {
    const schema = z.object({
      a: z.string().refine((v) => v.length > 3, 'a must exceed 3 chars'),
    });

    expect(project(schema, { a: 'x' }, 'Ctx').rows[0].issueCode).toBe(
      project(schema, { a: 'yy' }, 'Ctx').rows[0].issueCode
    );
  });

  it('classes an interpolated secret without letting a fragment of it through', () => {
    const schema = z.object({
      token: z.any().superRefine((val, ctx) => {
        ctx.addIssue({ code: 'custom', message: `rejected ${String(val)}` });
      }),
    });

    const projection = project(schema, { token: 'sk_live_51H8xQe0000LEAKME' }, 'Ctx');

    expect(wire(projection)).not.toContain('sk_live_');
    expect(wire(projection)).not.toContain('rejected');
    expect(String(projection.rows[0].issueCode)).toMatch(/^shape:[a9xps]+$/);
  });

  // -------------------------------------------------------------------------
  // The params allowlist is a KEY-NAME allowlist, so the only thing standing
  // between an author-chosen value and `issueCode` is which key it sits under
  // plus REFINEMENT_ID's shape test. Both halves are asserted here.
  // -------------------------------------------------------------------------

  it('does NOT read params.code — the one name that reads like "the value"', () => {
    // REGRESSION: `code` was on REFINEMENT_ID_KEYS. An author writing
    // `params: { code: order.customerCode }` shipped that value verbatim:
    // executed against the pre-fix tree, "alice" -> issueCode "alice",
    // "acme-corp-tenant" -> verbatim, "bob.smith" -> verbatim. Only the
    // scrubbers stood in the way, and none of those three trip a scrubber.
    for (const value of ['alice', 'acme-corp-tenant', 'bobsmith']) {
      const schema = z.string().superRefine((_v, ctx) => {
        ctx.addIssue({ code: 'custom', message: 'value rejected', params: { code: value } });
      });

      const projection = project(schema, 'x', 'Ctx');

      expect(wire(projection)).not.toContain(value);
      // Identity is not lost — it falls through to the shape discriminator.
      expect(String(projection.rows[0].issueCode)).toMatch(/^shape:[a9xps]+$/);
    }
  });

  it('refuses a value-shaped id under the four remaining param names', () => {
    // REFINEMENT_ID used to accept dots and colons, which is the vocabulary of
    // a hostname, an address or a dotted username — not of a rule name.
    const valueShaped = ['bob.smith', 'mail.acmecorp.example', '2001:db8::42', '9f3a2b1c'];

    for (const key of ['id', 'rule', 'refinement', 'name']) {
      for (const value of valueShaped) {
        const schema = z.string().superRefine((_v, ctx) => {
          ctx.addIssue({ code: 'custom', message: 'value rejected', params: { [key]: value } });
        });

        const projection = project(schema, 'x', 'Ctx');

        expect(wire(projection)).not.toContain(value);
        expect(String(projection.rows[0].issueCode)).toMatch(/^shape:[a9xps]+$/);
      }
    }
  });

  it('still accepts a genuine, identifier-shaped refinement id under each name', () => {
    for (const key of ['id', 'rule', 'refinement', 'name']) {
      const schema = z.string().superRefine((_v, ctx) => {
        ctx.addIssue({
          code: 'custom',
          message: 'x',
          params: { [key]: 'period_end_shape' },
        });
      });

      expect(project(schema, 'x', 'Ctx').rows[0].issueCode).toBe('period_end_shape');
    }

    const kebab = z.string().superRefine((_v, ctx) => {
      ctx.addIssue({ code: 'custom', message: 'x', params: { rule: 'must-exceed-min' } });
    });
    expect(project(kebab, 'x', 'Ctx').rows[0].issueCode).toBe('must-exceed-min');
  });
});

// ===========================================================================
// DEFECT 8 — issueCount carried three incompatible meanings
// ===========================================================================
describe('DEFECT 8 — the unrecognized-key count has its own name', () => {
  it('reports key_count on the row and issueCount only as the true total', () => {
    const projection = project(
      z.strictObject({ id: z.string() }),
      { id: 'x', authorization_token: 'sk_live_XKCD', tracking: 1 },
      'Ctx'
    );

    expect(projection.rows[0]).toMatchObject({ code: 'unrecognized_keys', key_count: 2 });
    expect(projection.rows[0]).not.toHaveProperty('issueCount');
    expect(projection.issueCount).toBe(1);
  });

  it('still drops the payload-derived key NAMES', () => {
    const projection = project(
      z.strictObject({ id: z.string() }),
      { id: 'x', authorization_token: 'sk_live_XKCD', tracking: 1 },
      'Ctx'
    );

    expect(wire(projection)).not.toContain('authorization_token');
    expect(wire(projection)).not.toContain('sk_live_XKCD');
    expect(wire(projection)).not.toContain('tracking');
  });

  it('keeps issueCount meaning the TRUE total on the truncation sentinel', () => {
    const shape: Record<string, z.ZodTypeAny> = {};
    const payload: Record<string, unknown> = {};
    for (let i = 0; i < MAX_PROJECTED_ISSUES + 5; i += 1) {
      shape[`f${i}`] = z.string();
      payload[`f${i}`] = i;
    }

    const projection = project(z.object(shape), payload, 'Ctx');
    const sentinel = projection.rows.find((row) => row.code === 'projection_truncated')!;

    expect(sentinel.issueCount).toBe(MAX_PROJECTED_ISSUES + 5);
    expect(projection.issueCount).toBe(MAX_PROJECTED_ISSUES + 5);
  });
});

// ===========================================================================
// DEFECT 9 — exports that nothing referenced
// ===========================================================================
describe('DEFECT 9 — ROOT_PATH and typeNameOf are part of the contract', () => {
  it('ROOT_PATH is the documented sentinel for an empty path', () => {
    expect(ROOT_PATH).toBe('(root)');
    expect(project(z.object({ a: z.string() }), null).rows[0].path).toBe(ROOT_PATH);
  });

  it('typeNameOf is finer than typeof exactly where that is diagnostic', () => {
    expect(typeNameOf(null)).toBe('null');
    expect(typeNameOf([])).toBe('array');
    expect(typeNameOf(new Date())).toBe('date');
    expect(typeNameOf(Number.NaN)).toBe('nan');
    expect(typeNameOf(1772940425)).toBe('number');
    expect(typeNameOf('1772940425')).toBe('string');
    expect(typeNameOf(undefined)).toBe('undefined');
  });
});

// ===========================================================================
// Registry — the truncation priority hook, and that it has not silently grown
// ===========================================================================
describe('safe-field registry', () => {
  it('answers enrollment without running the describer', () => {
    expect(
      isSafeFieldEnrolled('ColonelOrganizationDetailResponse', 'record.subscription_period_end')
    ).toBe(true);
    expect(isSafeFieldEnrolled('ColonelOrganizationDetailResponse', 'record.owner_email')).toBe(
      false
    );
    expect(isSafeFieldEnrolled(undefined, 'record.subscription_period_end')).toBe(false);
  });

  it('is still exactly one entry', () => {
    expect(enrolledSafeFieldKeys()).toEqual([
      'ColonelOrganizationDetailResponse|record.subscription_period_end',
    ]);
  });
});

// ===========================================================================
// The floor this branch exists for, asserted at projection level
// ===========================================================================
describe('THE FLOOR — the epoch tuple survives every change above', () => {
  it('reads path, code, expected and received off the projection alone', () => {
    const schema = z.object({ record: z.object({ subscription_period_end: z.string() }) });

    const projection = project(
      schema,
      { record: { subscription_period_end: 1772940425 } },
      'ColonelOrganizationDetailResponse'
    );

    expect(projection.rows[0]).toMatchObject({
      path: 'record.subscription_period_end',
      code: 'invalid_type',
      expected: 'string',
      received: 'number',
    });
    expect(projection.paths).toEqual(['record.subscription_period_end']);
    expect(wire(projection)).not.toContain('1772940425');
  });
});
