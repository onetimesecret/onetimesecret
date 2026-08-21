// src/tests/utils/diagnostics/diagnosticsSurfaceClaims.spec.ts
//
// EXECUTED SURFACE CLAIMS.
//
// The recurring defect in this effort is a comment asserting a guarantee the
// code does not deliver. The riskiest sub-species is a claim about WHICH
// SURFACE a field lands on — tag, extra, or message — because
// `src/utils/schemaValidation.ts` makes that a privacy-load-bearing statement
// ("anything placed in extras is UNSCRUBBED BY CONSTRUCTION") and then got it
// wrong twice in the same docblock, calling `apiRoute` an EXTRA when
// `TAG_FIELDS` in diagnostics.service.ts has always routed it to `setTag`.
//
// So every surface claim in the owned files is pinned here by running it.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { normalize } from '@sentry/core';
import { z } from 'zod';

vi.mock('@/services/logging.service', () => ({
  loggingService: { error: vi.fn(), warn: vi.fn(), info: vi.fn(), debug: vi.fn(), banner: vi.fn() },
}));

import type { BrowserClient, Scope } from '@sentry/vue';
import { initDiagnostics } from '@/services/diagnostics.service';
import { gracefulParse } from '@/utils/schemaValidation';
import { projectSchemaIssues } from '@/utils/diagnostics/schemaIssueProjection';
import { resetApiRouteContext, setCurrentApiRoute } from '@/utils/diagnostics/apiRouteContext';

// ---------------------------------------------------------------------------
// A Sentry scope that records which surface each key was written to.
// ---------------------------------------------------------------------------

interface RecordedScope {
  tags: Record<string, unknown>;
  extras: Record<string, unknown>;
}

let recorded: RecordedScope;

function makeScope(): Scope {
  const scope = {
    clone: () => scope,
    setTag: (key: string, value: unknown) => {
      recorded.tags[key] = value;
      return scope;
    },
    setExtras: (values: Record<string, unknown>) => {
      Object.assign(recorded.extras, values);
      return scope;
    },
  };
  return scope as unknown as Scope;
}

const captured: Array<Error> = [];

function makeClient(): BrowserClient {
  return {
    captureException: (error: Error) => {
      captured.push(error);
      return 'id';
    },
  } as unknown as BrowserClient;
}

function source(relativePath: string): string {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8');
}

describe('which surface each emitted field lands on', () => {
  beforeEach(() => {
    recorded = { tags: {}, extras: {} };
    captured.length = 0;
    resetApiRouteContext();
    initDiagnostics(makeClient(), makeScope());
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('DEV', false as never);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    resetApiRouteContext();
  });

  function parseAndCapture(): void {
    setCurrentApiRoute('/api/colonel/organizations/org_9f3a2b1c8d7e6f50');
    gracefulParse(z.object({ record: z.object({ n: z.string() }) }), { record: { n: 7 } }, 'Ctx');
  }

  it('apiRoute is a TAG, not an extra', () => {
    parseAndCapture();

    expect(recorded.tags).toHaveProperty('apiRoute', '/api/colonel/organizations/:org_id');
    expect(recorded.extras).not.toHaveProperty('apiRoute');
  });

  it('schema and schemaField are TAGS; issueCount and issues are EXTRAS', () => {
    parseAndCapture();

    expect(Object.keys(recorded.tags).sort()).toEqual(['apiRoute', 'schema', 'schemaField']);
    expect(Object.keys(recorded.extras).sort()).toEqual(['issueCount', 'issues']);
  });

  it('an unknown route is omitted from BOTH surfaces rather than sent as undefined', () => {
    gracefulParse(z.object({ a: z.string() }), { a: 1 }, 'Ctx');

    expect(recorded.tags).not.toHaveProperty('apiRoute');
    expect(recorded.extras).not.toHaveProperty('apiRoute');
  });

  it('the resolved tenant id never reaches any surface', () => {
    parseAndCapture();

    const wire = JSON.stringify({ ...recorded, message: captured.at(-1)?.message });
    expect(wire).not.toContain('org_9f3a2b1c8d7e6f50');
  });
});

describe('neither extras nor tags are scrubbed on the way out', () => {
  // schemaValidation.ts calls extras "the sharp edge" because
  // `createBeforeSendHandler` does not touch them. Tags are in the same
  // position — the handler names request.url, the Referer header, transaction,
  // user, breadcrumbs and the exception values, and nothing else. If a scrub
  // for either surface is ever added there, this guard fails and the prose in
  // schemaValidation.ts has to be relaxed to match.
  const HANDLER = source('src/plugins/core/enableDiagnostics.ts');
  const body = HANDLER.slice(
    HANDLER.indexOf('function createBeforeSendHandler'),
    HANDLER.indexOf('function createBeforeSendTransactionHandler')
  );

  it('createBeforeSendHandler was found and is non-empty', () => {
    expect(body.length).toBeGreaterThan(200);
  });

  it('createBeforeSendHandler never reads or writes event.extra', () => {
    expect(body).not.toContain('event.extra');
  });

  it('createBeforeSendHandler never reads or writes event.tags', () => {
    expect(body).not.toContain('event.tags');
  });
});

describe('flat rows survive Sentry normalizeDepth; nested ones would not', () => {
  // `normalizeDepth` defaults to 3 and is applied as `normalize(event.extra, 3)`
  // (@sentry/core prepareEvent.js). The projection's docblock claims flat rows
  // survive that budget and one more nesting level degrades to `[Object]`.
  const extras = { issues: [{ path: 'a.b', code: 'invalid_type', received: 'number' }] };

  it('the shape the projection actually emits survives intact', () => {
    expect(normalize(extras, 3)).toEqual(extras);
  });

  it('one more nesting level degrades to [Object]', () => {
    expect(normalize({ issues: { '0': { detail: { path: 'a.b' } } } }, 3)).toEqual({
      issues: { '0': { detail: '[Object]' } },
    });
  });

  it('every emitted row value is a primitive, so no row can degrade', () => {
    const result = z.object({ a: z.string(), b: z.number() }).safeParse({ a: 1, b: 'x' });
    const rows = projectSchemaIssues(result.error!, { a: 1, b: 'x' }, 'Ctx').rows;

    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) {
      for (const value of Object.values(row)) {
        expect(['string', 'number', 'boolean']).toContain(typeof value);
      }
    }
  });
});

describe('what REFINEMENT_ID actually bounds', () => {
  function issueCodeFor(params: Record<string, unknown>): string | undefined {
    const schema = z.string().superRefine((_v, ctx) => {
      ctx.addIssue({ code: 'custom', message: 'value rejected', params });
    });
    const result = schema.safeParse('x');
    return projectSchemaIssues(result.error!, 'x', 'Ctx').rows[0]?.issueCode;
  }

  it('bounds PUNCTUATION: dots and colons fall through to the shape discriminator', () => {
    expect(issueCodeFor({ name: 'bob.smith' })).toMatch(/^shape:/);
    expect(issueCodeFor({ id: '2001:db8::42' })).toMatch(/^shape:/);
  });

  it('bounds anything the scrubbers recognize, via safeConstant', () => {
    expect(issueCodeFor({ id: 'alice@example.com' })).toMatch(/^shape:/);
    expect(issueCodeFor({ id: 'sk_live_51H8xQzABCDEF' })).toMatch(/^shape:/);
    expect(issueCodeFor({ id: 'org_9f3a2b1c8d7e6f50' })).toMatch(/^shape:/);
  });

  it('refuses `code` by key, whatever it holds', () => {
    expect(issueCodeFor({ code: 'alice' })).toMatch(/^shape:/);
  });

  it('does NOT bound a value-shaped word under the four accepted names', () => {
    // This is the residual risk documented on REFINEMENT_ID_KEYS. It is author
    // discipline, not a control — asserted so the docblock cannot drift back to
    // claiming REFINEMENT_ID bounds it. If a registry of known refinement ids
    // is ever added, this expectation is what changes.
    expect(issueCodeFor({ id: 'alice' })).toBe('alice');
    expect(issueCodeFor({ refinement: 'acme-corp-tenant' })).toBe('acme-corp-tenant');
  });

  it('nothing in src/schemas supplies params today, so the hole is unreachable', () => {
    for (const file of [
      'src/schemas/contracts/custom-domain/sso-config.ts',
      'src/schemas/contracts/custom-domain/signup-config.ts',
    ]) {
      expect(source(file)).toContain('ctx.addIssue');
      expect(source(file)).not.toMatch(/ctx\.addIssue\(\{[^}]*params:/s);
    }
  });
});

describe('Zod built-in messages, and why none of them ship', () => {
  it("a built-in message DOES interpolate a payload-derived KEY", () => {
    const result = z.object({ a: z.string() }).strict().safeParse({ a: 'x', authorization_token: 'zz' });

    expect(result.error!.issues[0].message).toContain('authorization_token');
  });

  it('that key reaches no emitted field: only the count survives', () => {
    const data = { a: 'x', authorization_token: 'zz' };
    const result = z.object({ a: z.string() }).strict().safeParse(data);
    const projection = projectSchemaIssues(result.error!, data, 'Ctx');

    expect(JSON.stringify(projection)).not.toContain('authorization_token');
    expect(projection.rows[0]).toMatchObject({ code: 'unrecognized_keys', key_count: 1 });
    expect(projection.redactionSignals).toEqual([]);
  });

  it('a message the scrubbers DO recognize yields only the sentinel', () => {
    const schema = z.object({
      token: z.any().superRefine((val, ctx) => {
        ctx.addIssue({ code: 'custom', message: `rejected ${String(val)}` });
      }),
    });
    const data = { token: 'tester@example.com' };
    const projection = projectSchemaIssues(schema.safeParse(data).error!, data, 'Ctx');

    expect(projection.redactionSignals).toEqual(['[EMAIL_REDACTED]']);
    expect(JSON.stringify(projection)).not.toContain('tester@example.com');
  });
});
