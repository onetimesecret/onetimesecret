import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { responseSchemas as incoming } from '@/schemas/api/incoming/responses/registry';
import { responseSchemas as internal } from '@/schemas/api/internal/responses/registry';
import { responseSchemas as v1 } from '@/schemas/api/v1/responses/registry';
import { responseSchemas as v2 } from '@/schemas/api/v2/responses/registry';
import { responseSchemas as v3 } from '@/schemas/api/v3/responses/registry';
import { allSchemas, checkPayload, closest, counted, type CheckResult } from '@/schemas/check';
import { loggersSchema } from '@/schemas/contracts/config/logging';
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

  it('accepts custom logger keys covered by the logging catchall (F2)', () => {
    const input = { App: 'info', Custom: 'debug' };
    expect(loggersSchema.safeParse(input).success).toBe(true);
    expect(checkPayload(loggersSchema, input)).toEqual({
      success: true,
      issueCount: 0,
      groups: new Map(),
      undeclared: [],
    });
  });

  it('does not label passthrough keys as stripped or expand their unknown values (F2)', () => {
    const schema = z.object({ id: z.number() }).passthrough();
    const result = checkPayload(schema, {
      id: 1,
      extra: { 'private-nested-key': 'private-value' },
    });
    expect(result.success).toBe(true);
    expect(result.undeclared).toEqual([]);
    expect(result.groups.size).toBe(0);
    expect(reportText(result)).not.toContain('private-');
  });

  it('walks typed catchall values and only reports their stripped nested keys (F2)', () => {
    const schema = z.object({}).catchall(z.object({ id: z.number() }));
    const result = checkPayload(schema, {
      valid: { id: 1, extra: true },
      invalid: { id: 'private-value', extra: true },
    });
    expect(result.success).toBe(false);
    expect(result.issueCount).toBe(1);
    expect(result.undeclared).toEqual(['valid.extra', 'invalid.extra']);
    expect(counted(result.groups.get('invalid')!.problems)).toEqual([
      'id: expected number, got string(13)',
    ]);
  });

  it('reports rejected strict-object keys as errors, not stripped keys (F2)', () => {
    const result = checkPayload(z.strictObject({ id: z.number() }), { id: 1, extra: true });
    expect(result.success).toBe(false);
    expect(result.issueCount).toBe(1);
    expect(result.undeclared).toEqual([]);
    expect(result.groups.get('(root)')!.undeclared.size).toBe(0);
    expect(result.groups.get('(root)')!.problems.size).toBe(1);
  });

  it('reports stripped keys from the successful registered login union branch (F3)', () => {
    const schema = allSchemas().get('v3.login')!;
    const input = { success: 'ok', extra: true };
    expect(schema.safeParse(input).success).toBe(true);
    const result = checkPayload(schema, input);
    expect(result.success).toBe(true);
    expect(result.issueCount).toBe(0);
    expect(result.undeclared).toEqual(['extra']);
    expect(result.groups.get('(root)')!.undeclared).toEqual(new Set(['extra']));
  });

  it('walks successful nested discriminated-union branches in arrays (F3)', () => {
    const row = z.discriminatedUnion('kind', [
      z.object({ kind: z.literal('number'), value: z.number() }),
      z.object({ kind: z.literal('text'), value: z.string() }),
    ]);
    const schema = z.object({ rows: z.array(row.optional()) });
    const result = checkPayload(schema, {
      rows: [
        { kind: 'number', value: 1, extra: true },
        { kind: 'text', value: 'private-value', other: true },
        { kind: 'invalid', extra: true },
      ],
    });
    expect(result.success).toBe(false);
    expect(result.issueCount).toBe(1);
    expect(result.undeclared).toEqual(['rows[*].extra', 'rows[*].other']);
    expect(reportText(result)).not.toContain('private-value');
  });

  it('uses the first successful union branch without probing later branches (F3)', () => {
    let laterCalls = 0;
    const schema = z.union([
      z.object({ id: z.number() }).transform(({ id }) => String(id)),
      z.object({ id: z.number(), extra: z.boolean() }).transform((value) => {
        laterCalls++;
        return value;
      }),
    ]);
    expect(checkPayload(schema, { id: 1, extra: true }).undeclared).toEqual(['extra']);
    expect(laterCalls).toBe(0);
  });

  it('keeps failed unions opaque, including when catch suppresses their diagnostics (F3)', () => {
    const schema = z.union([z.object({ id: z.number() }), z.object({ label: z.string() })]);
    const input = { id: 'private-value', extra: true };
    const failed = checkPayload(schema, input);
    expect(failed.success).toBe(false);
    expect(failed.issueCount).toBe(1);
    expect(failed.undeclared).toEqual([]);
    expect(failed.groups.get('(root)')!.problems.size).toBe(1);
    expect(reportText(failed)).not.toContain('private-value');
    expect(checkPayload(schema.catch({ id: 0 }), input)).toEqual({
      success: true,
      issueCount: 0,
      groups: new Map(),
      undeclared: [],
    });
  });

  it('does not expand unions rejected or throwing beneath diagnostic-suppressing wrappers (F3)', () => {
    const options = [z.object({ id: z.number() }), z.object({ label: z.string() })] as const;
    const rejected = z
      .union(options)
      .refine(() => false)
      .catch({ id: 0 });

    const suppressed = z
      .union([
        z.unknown().transform(() => {
          throw new Error('transform failed');
        }),
        z.string(),
      ])
      .nullable();
    const input = { id: 1, extra: true };
    expect(checkPayload(rejected, input).undeclared).toEqual([]);
    expect(checkPayload(suppressed, null).success).toBe(true);
    expect(closest(input, new Map([['rejected', rejected]]))).toEqual([
      { name: 'rejected', issues: 0, matched: 1, undeclared: 0 },
    ]);
    expect(closest(null, new Map([['suppressed', suppressed]]))).toEqual([
      { name: 'suppressed', issues: 0, matched: 1, undeclared: 0 },
    ]);
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

  it('counts accepted catchall and passthrough values without counting rejected keys (F2)', () => {
    const input = { id: 1, valid: 2, invalid: 'private-value' };
    const schemas = new Map<string, z.ZodType>([
      ['catchall', z.object({ id: z.number() }).catchall(z.number())],
      ['passthrough', z.object({ id: z.number() }).passthrough()],
      ['strict', z.strictObject({ id: z.number() })],
      ['strip', z.object({ id: z.number() })],
    ]);
    expect(closest(input, schemas, 4)).toEqual([
      { name: 'passthrough', issues: 0, matched: 3, undeclared: 0 },
      { name: 'catchall', issues: 1, matched: 2, undeclared: 0 },
      { name: 'strip', issues: 0, matched: 1, undeclared: 2 },
      { name: 'strict', issues: 1, matched: 1, undeclared: 0 },
    ]);
  });

  it('ranks successful unions by their branch leaves instead of one opaque leaf (F3)', () => {
    const schemas = new Map<string, z.ZodType>([
      ['weak', z.object({ success: z.string() })],
      ['v3.login', allSchemas().get('v3.login')!],
    ]);
    expect(closest({ success: 'ok', mfa_required: true, extra: true }, schemas)).toEqual([
      { name: 'v3.login', issues: 0, matched: 2, undeclared: 1 },
      { name: 'weak', issues: 0, matched: 1, undeclared: 2 },
    ]);
  });

  it('preserves failed and diagnostic-suppressed union leaf scores (F3)', () => {
    const schema = z.union([z.object({ id: z.number() }), z.object({ label: z.string() })]);
    expect(
      closest(
        { id: 'private-value', extra: true },
        new Map<string, z.ZodType>([
          ['failed', schema],
          ['suppressed', schema.catch({ id: 0 })],
        ])
      )
    ).toEqual([
      { name: 'suppressed', issues: 0, matched: 1, undeclared: 0 },
      { name: 'failed', issues: 1, matched: 0, undeclared: 0 },
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

describe('coverage QA regressions', () => {
  it.each(['kind', ''])(
    'never starts bypassed async transforms with discriminator %j (QA-01/QA-03)',
    async (discriminator) => {
      const root = fileURLToPath(new URL('../../../', import.meta.url));
      const bundle = await build({
        absWorkingDir: root,
        stdin: {
          resolveDir: root,
          loader: 'ts',
          contents: `
          import { z } from 'zod';
          import { checkPayload, closest } from './src/schemas/check';
          let calls = 0;
          const asyncValue = z.unknown().transform(async () => {
            calls++;
            throw new Error('async rejection');
          });
          const union = z.union([asyncValue, z.string()]);
          const defaultUnion = z.union([z.literal('fallback'), asyncValue]);
          const normalUnion = z.union([
            z.object({ id: z.number() }), z.object({ label: z.string() }),
          ]);
          const discriminator = ${JSON.stringify(discriminator)};
          const discriminated = z.discriminatedUnion(discriminator, [
            z.object({ [discriminator]: z.literal('async'), value: asyncValue }),
            z.object({ [discriminator]: z.literal('sync'), value: z.string() }),
          ]);
          const cases = [
            [union.nullable(), null],
            [union.optional(), undefined],
            [union.default('fallback'), undefined],
            [union.default('fallback').catch('fallback'), undefined],
            [union.nullable().catch('fallback'), null],
            [z.lazy(() => union.nullable()), null],
            [z.object({ value: union.nullable() }), { value: null }],
            [defaultUnion.prefault('fallback'), undefined],
            [z.union([union.default('fallback'), z.string()]), undefined],
            [z.preprocess(() => 'fallback', defaultUnion), null],
            [discriminated, { [discriminator]: 'sync', value: 'ok', extra: true }, 2, ['extra']],
            [discriminated, Object.assign(Object.create(null), { [discriminator]: 'sync', value: 'ok' })],
            [z.object({
              preprocessed: z.preprocess(() => 'fallback', defaultUnion),
              normal: normalUnion,
            }), { preprocessed: null, normal: { id: 1, extra: true } }, 2, ['normal.extra']],
          ];
          for (const [schema, input, matched = 1, undeclared = []] of cases) {
            if (!schema.safeParse(input).success) throw new Error('invalid fixture');
            const report = checkPayload(schema, input);
            const candidates = closest(input, new Map([['test', schema]]));
            await new Promise((resolve) => setImmediate(resolve));
            if (!report.success || JSON.stringify(report.undeclared) !== JSON.stringify(undeclared)) {
              throw new Error('check failed');
            }
            if (candidates.length !== 1 || candidates[0].issues !== 0 || candidates[0].matched !== matched || candidates[0].undeclared !== undeclared.length) {
              throw new Error('candidate lost');
            }
          }
          await new Promise((resolve) => setImmediate(resolve));
          if (calls !== 0) throw new Error('bypassed transform invoked');
        `,
        },
        bundle: true,
        platform: 'node',
        format: 'esm',
        write: false,
        logLevel: 'silent',
      });
      expect(() =>
        execFileSync(process.execPath, ['--unhandled-rejections=strict', '--input-type=module'], {
          input: bundle.outputFiles[0].text,
          timeout: 5000,
          stdio: 'pipe',
        })
      ).not.toThrow();
    }
  );

  it.each(['optional', 'nullable', 'default', 'prefault', 'catch'] as const)(
    'still traverses %s-wrapped unions when supplied input reaches the union (QA-01)',
    (wrapper) => {
      const union = z.union([z.object({ id: z.number() }), z.object({ label: z.string() })]);
      const schemas = {
        optional: union.optional(),
        nullable: union.nullable(),
        default: union.default({ id: 0 }),
        prefault: union.prefault({ id: 0 }),
        catch: union.catch({ id: 0 }),
      };
      const schema = schemas[wrapper];
      const input = { id: 1, extra: true };
      expect(checkPayload(schema, input).undeclared).toEqual(['extra']);
      expect(closest(input, new Map([['wrapped', schema]]))).toEqual([
        { name: 'wrapped', issues: 0, matched: 1, undeclared: 1 },
      ]);
    }
  );

  it.each(['toString', 'constructor', '__proto__'])(
    'treats inherited shape name %s as a stripped key in the login union (QA-02)',
    (key) => {
      const schema = allSchemas().get('v3.login')!;
      const input = JSON.parse(`{"success":"ok","${key}":"private-value"}`);
      expect(schema.safeParse(input).success).toBe(true);
      const result = checkPayload(schema, input);
      expect(result.success).toBe(true);
      expect(result.undeclared).toEqual([key]);
      expect(reportText(result)).not.toContain('private-value');
      expect(closest(input, new Map([['v3.login', schema]]))).toEqual([
        { name: 'v3.login', issues: 0, matched: 1, undeclared: 1 },
      ]);
    }
  );

  it('still visits explicitly declared prototype-named fields (QA-02)', () => {
    const schema = z.union([
      z.object({ toString: z.string(), constructor: z.number() }),
      z.object({ id: z.number() }),
    ]);
    const input = JSON.parse('{"toString":"private-value","constructor":1}');
    expect(checkPayload(schema, input).undeclared).toEqual([]);
    expect(closest(input, new Map([['declared', schema]]))).toEqual([
      { name: 'declared', issues: 0, matched: 2, undeclared: 0 },
    ]);
  });

  it.each(['toString', 'constructor', '__proto__'])(
    'treats inherited shape name %s as a stripped key within typed catchalls (QA-02)',
    (key) => {
      const schema = z.object({}).catchall(z.object({ id: z.number() }));
      const input = JSON.parse(`{"row":{"id":1,"${key}":"private-value"}}`);
      expect(schema.safeParse(input).success).toBe(true);
      const result = checkPayload(schema, input);
      expect(result.success).toBe(true);
      expect(result.undeclared).toEqual([`row.${key}`]);
      expect(reportText(result)).not.toContain('private-value');
      expect(closest(input, new Map([['catchall', schema]]))).toEqual([
        { name: 'catchall', issues: 0, matched: 1, undeclared: 1 },
      ]);
    }
  );
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
