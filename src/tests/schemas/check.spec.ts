import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { responseSchemas as incoming } from '@/schemas/api/incoming/responses/registry';
import { responseSchemas as internal } from '@/schemas/api/internal/responses/registry';
import { responseSchemas as v1 } from '@/schemas/api/v1/responses/registry';
import { responseSchemas as v2 } from '@/schemas/api/v2/responses/registry';
import { responseSchemas as v3 } from '@/schemas/api/v3/responses/registry';
import { allSchemas, checkPayload, closest, counted, type CheckResult } from '@/schemas/check';
import { schemaRegistry } from '@/schemas/registry';

function reportText(result: CheckResult): string {
  return JSON.stringify({
    ...result,
    groups: [...result.groups].map(([path, group]) => ({
      path,
      missing: [...group.missing],
      problems: [...group.problems],
      undeclared: [...group.undeclared],
    })),
  });
}

describe('allSchemas', () => {
  it('preserves every CLI registry name, schema identity, and insertion order', () => {
    const expected = new Map<string, z.ZodType>();
    for (const [prefix, registry] of Object.entries({ v1, v2, v3, incoming, internal })) {
      for (const [key, schema] of Object.entries(registry))
        expected.set(`${prefix}.${key}`, schema);
    }
    for (const [key, schema] of Object.entries(schemaRegistry)) expected.set(key, schema);

    const schemas = allSchemas();
    expect([...schemas.keys()]).toEqual([...expected.keys()]);
    for (const [name, schema] of expected) expect(schemas.get(name)).toBe(schema);
    expect(schemas.get('api/v3/secret-response')).toBe(schemas.get('v3.secret'));
    expect(schemas.get('config/auth')).toBe(schemaRegistry['config/auth']);
    expect(schemas.get('config/billing')).toBe(schemaRegistry['config/billing']);
    expect(schemas.get('config/static')).toBe(schemaRegistry['config/static']);
  });

  it('returns an independent map on each call', () => {
    const schemas = allSchemas();
    schemas.clear();
    expect(allSchemas().size).toBeGreaterThan(0);
  });

  it('bundles the shared checker and its registries for browsers without Node dependencies', async () => {
    const result = await build({
      absWorkingDir: fileURLToPath(new URL('../../../', import.meta.url)),
      entryPoints: ['src/schemas/check.ts'],
      bundle: true,
      platform: 'browser',
      format: 'esm',
      write: false,
      logLevel: 'silent',
    });
    expect(result.errors).toEqual([]);
    expect(result.outputFiles).toHaveLength(1);
  });
});

describe('checkPayload', () => {
  it('reports successful validation without exposing the parsed value', () => {
    expect(checkPayload(z.string(), 'private-value')).toEqual({
      success: true,
      issueCount: 0,
      groups: new Map(),
      undeclared: [],
    });
  });

  it('reports undeclared keys on success without walking record keys or unknown values', () => {
    const schema = z.object({
      rows: z.array(z.object({ id: z.number() })),
      metadata: z.record(z.string(), z.unknown()),
    });
    const input = {
      rows: [
        { id: 1, extra: { 'private-nested-key': 'private-value' } },
        { id: 2, extra: 'private-value', other: true },
      ],
      metadata: { 'private-record-key': { 'private-nested-key': 'private-value' } },
      extra: 'private-value',
    };
    const result = checkPayload(schema, input);

    expect(result.success).toBe(true);
    expect(result.issueCount).toBe(0);
    expect(result.undeclared).toEqual(['rows[*].extra', 'rows[*].other', 'extra']);
    expect(result.groups).toEqual(
      new Map([
        [
          'rows[*]',
          { missing: new Map(), problems: new Map(), undeclared: new Set(['extra', 'other']) },
        ],
        ['(root)', { missing: new Map(), problems: new Map(), undeclared: new Set(['extra']) }],
      ])
    );
    expect(reportText(result)).not.toContain('private-');
    expect(input.rows[0]).toHaveProperty('extra');
  });

  it('groups repeated missing fields and problems across array items on failure', () => {
    const schema = z.object({
      rows: z.array(z.object({ id: z.number(), label: z.string() })),
      required: z.string(),
    });
    const result = checkPayload(schema, {
      rows: [
        { id: 'private-value', extra: true },
        { id: 'private-value', extra: false },
      ],
      topExtra: { nested: 'private-value' },
    });
    const problem = 'id: expected number, got string(13)';

    expect(result.success).toBe(false);
    expect(result.issueCount).toBe(5);
    expect(result.groups).toEqual(
      new Map([
        [
          'rows[*]',
          {
            missing: new Map([['label', 2]]),
            problems: new Map([[problem, 2]]),
            undeclared: new Set(['extra']),
          },
        ],
        [
          '(root)',
          {
            missing: new Map([['required', 1]]),
            problems: new Map(),
            undeclared: new Set(['topExtra']),
          },
        ],
      ])
    );
    expect(result.undeclared).toEqual(['rows[*].extra', 'topExtra']);
    expect(counted(result.groups.get('rows[*]')!.missing)).toEqual(['label (x2)']);
    expect(counted(result.groups.get('rows[*]')!.problems)).toEqual([`${problem} (x2)`]);
    expect(reportText(result)).not.toContain('private-value');
  });

  it.each([undefined, null, false, 123, 'private-value', ['private-value']])(
    'describes invalid root input %j without classifying it as a missing field',
    (input) => {
      const result = checkPayload(z.object({ id: z.number() }), input);
      expect(result.success).toBe(false);
      expect(result.issueCount).toBe(1);
      expect(result.groups.get('(root)')!.missing.size).toBe(0);
      expect(result.groups.get('(root)')!.problems.size).toBe(1);
      expect(reportText(result)).not.toContain('private-value');
    }
  );

  it('introspects optional, nullable, default, lazy, preprocess, and transform wrappers', () => {
    const object = z.object({ id: z.number() });
    const schema = z.object({
      optional: object.optional(),
      nullable: object.nullable(),
      defaulted: object.default({ id: 0 }),
      lazy: z.lazy(() => object),
      preprocessed: z.preprocess((value) => value, object),
      transformed: object.transform(({ id }) => String(id)),
    });
    const input = Object.fromEntries(
      Object.keys(schema.shape).map((key) => [key, { id: 1, extra: 'private-value' }])
    );
    const result = checkPayload(schema, input);
    expect(result.success).toBe(true);
    expect(result.undeclared).toEqual(Object.keys(schema.shape).map((key) => `${key}.extra`));
    expect(reportText(result)).not.toContain('private-value');
  });

  it('keeps enum expectations and standard constraint messages while hiding supplied values', () => {
    const schema = z.object({
      state: z.enum(['new', 'revealed']),
      email: z.email(),
      prefix: z.string().startsWith('public-prefix'),
      suffix: z.string().endsWith('public-suffix'),
      includes: z.string().includes('public-fragment'),
      pattern: z.string().regex(/^public-pattern$/),
      minimum: z.string().min(100),
    });
    const input = Object.fromEntries(
      Object.keys(schema.shape).map((key) => [key, 'private-value'])
    );
    const hidden = checkPayload(schema, input);
    const shown = checkPayload(schema, input, true);

    expect(hidden.issueCount).toBe(7);
    expect(reportText(hidden)).not.toContain('private-value');
    expect(counted(hidden.groups.get('(root)')!.problems)).toContain(
      'state: expected "new" | "revealed", got string(13)'
    );
    expect(reportText(hidden)).toContain('Invalid email address');
    for (const line of shown.groups.get('(root)')!.problems.keys()) {
      expect(line).toContain('string(13) "private-value"');
    }
  });

  it('preserves custom messages, which callers must ensure do not embed private values', () => {
    const schema = z.string().superRefine((value, context) => {
      context.addIssue({ code: 'custom', message: `Rejected ${value}` });
    });
    expect(counted(checkPayload(schema, 'private-value').groups.get('(root)')!.problems)).toEqual([
      '(root): Rejected private-value (input: string(13))',
    ]);
  });

  it('propagates thrown parsing errors for the caller to catch', () => {
    const error = new Error('transform failed');
    const schema = z.string().transform(() => {
      throw error;
    });
    expect(() => checkPayload(schema, 'private-value')).toThrow(error);
    expect(() =>
      checkPayload(
        z.string().refine(async () => false),
        'private-value'
      )
    ).toThrow();
  });
});

describe('closest', () => {
  it('deduplicates aliases by identity, skips config schemas, and ranks by matched fields first', () => {
    const strong = z.object({ id: z.number(), label: z.string(), required: z.boolean() });
    const weak = z.object({ id: z.number() });
    const schemas = new Map<string, z.ZodType>([
      ['config/strong', strong],
      ['v3.strong', strong],
      ['api/v3/strong-response', strong],
      ['v3.weak', weak],
      ['v3.other', z.object({ other: z.boolean() })],
      ['config/only', z.unknown()],
    ]);
    const input = { id: 1, label: 'private-value', extra: true };

    expect(closest(input, schemas)).toEqual([
      { name: 'v3.strong', issues: 1, matched: 2, undeclared: 1 },
      { name: 'v3.weak', issues: 0, matched: 1, undeclared: 2 },
      { name: 'v3.other', issues: 1, matched: 0, undeclared: 3 },
    ]);
    expect(closest(input, schemas, 1)).toEqual([
      { name: 'v3.strong', issues: 1, matched: 2, undeclared: 1 },
    ]);
    expect(closest(input, schemas, 0)).toEqual([]);
  });

  it('breaks matched-field ties by issue count, then undeclared count, with stable registry order', () => {
    const schemas = new Map<string, z.ZodType>([
      ['more-issues', z.object({ id: z.number(), required: z.boolean() })],
      ['more-undeclared', z.object({ id: z.number() })],
      ['best', z.object({ id: z.number(), empty: z.object({}) })],
      ['tied', z.object({ id: z.number(), empty: z.object({}) })],
    ]);
    expect(closest({ id: 1, empty: {} }, schemas, 4)).toEqual([
      { name: 'best', issues: 0, matched: 1, undeclared: 0 },
      { name: 'tied', issues: 0, matched: 1, undeclared: 0 },
      { name: 'more-undeclared', issues: 0, matched: 1, undeclared: 1 },
      { name: 'more-issues', issues: 1, matched: 1, undeclared: 1 },
    ]);
  });

  it('skips schemas whose transforms or async refinements throw', () => {
    const schemas = new Map<string, z.ZodType>([
      [
        'throws',
        z.string().transform(() => {
          throw new Error('transform failed');
        }),
      ],
      ['async', z.string().refine(async () => false)],
      ['valid', z.string()],
    ]);
    expect(closest('private-value', schemas)).toEqual([
      { name: 'valid', issues: 0, matched: 1, undeclared: 0 },
    ]);
  });
});

describe('counted', () => {
  it('preserves insertion order and suffixes only repeated entries', () => {
    expect(counted(new Map())).toEqual([]);
    expect(
      counted(
        new Map([
          ['one', 1],
          ['many', 3],
          ['two', 2],
        ])
      )
    ).toEqual(['one', 'many (x3)', 'two (x2)']);
  });
});
