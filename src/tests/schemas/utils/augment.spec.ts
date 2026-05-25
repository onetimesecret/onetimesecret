// src/tests/schemas/utils/augment.spec.ts
//
// Tests the augment helper: leaf overrides, sub-tree recursion, wrapper
// unwrap/rewrap, catchall preservation, and the runtime unknown-key guard.

import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { augment } from '@/schemas/utils/augment';

describe('augment — leaf overrides', () => {
  it('applies .default() to a top-level scalar', () => {
    const contract = z.object({ host: z.string().optional() });
    const shape = augment(contract, {
      host: (h) => h.default('localhost:3000'),
    });

    expect(shape.parse({}).host).toBe('localhost:3000');
    expect(shape.parse({ host: 'example.com' }).host).toBe('example.com');
  });

  it('hands the leaf the unwrapped inner type so .int() / .min() resolve', () => {
    const contract = z.object({
      minimum_length: z.number().optional(),
    });

    const shape = augment(contract, {
      minimum_length: (n) => n.int().min(0).max(256).default(4),
    });

    expect(shape.parse({}).minimum_length).toBe(4);
    expect(shape.parse({ minimum_length: 10 }).minimum_length).toBe(10);
    expect(() => shape.parse({ minimum_length: 0.5 })).toThrow();
    expect(() => shape.parse({ minimum_length: 300 })).toThrow();
  });

  it('leaves siblings not mentioned in the tree untouched', () => {
    const contract = z.object({
      a: z.string().optional(),
      b: z.string().optional(),
      c: z.string().optional(),
    });

    const shape = augment(contract, {
      a: (s) => s.default('A'),
    });

    const parsed = shape.parse({});
    expect(parsed.a).toBe('A');
    expect(parsed.b).toBeUndefined();
    expect(parsed.c).toBeUndefined();
  });

  it('passes unwrapped ZodNumber for a .nullable() field', () => {
    const contract = z.object({
      port: z.number().nullable(),
    });

    const shape = augment(contract, {
      port: (n) => n.int().positive().default(587),
    });

    expect(shape.parse({}).port).toBe(587);
    expect(() => shape.parse({ port: 'nope' })).toThrow();
  });

  it('passes unwrapped ZodString for a .nullable().optional() (nullish) field', () => {
    const contract = z.object({
      label: z.string().nullable().optional(),
    });

    const shape = augment(contract, {
      label: (s) => s.default('x'),
    });

    // The shape replaces optional+nullable with a plain default; passing null
    // is no longer accepted unless the leaf re-applied .nullable().
    expect(shape.parse({}).label).toBe('x');
    expect(() => shape.parse({ label: null as unknown as string })).toThrow();
  });

  it('lets the leaf re-apply wrappers when the shape wants to preserve them', () => {
    const contract = z.object({
      label: z.string().nullable().optional(),
    });

    const shape = augment(contract, {
      label: (s) => s.nullable().default('x'),
    });

    expect(shape.parse({}).label).toBe('x');
    expect(shape.parse({ label: null }).label).toBeNull();
  });
});

describe('augment — sub-tree recursion', () => {
  it('recurses into a plain ZodObject field', () => {
    const contract = z.object({
      site: z.object({
        host: z.string().optional(),
        ssl: z.boolean().optional(),
      }),
    });

    const shape = augment(contract, {
      site: {
        host: (h) => h.default('localhost:3000'),
        ssl: (b) => b.default(false),
      },
    });

    const parsed = shape.parse({ site: {} });
    expect(parsed.site.host).toBe('localhost:3000');
    expect(parsed.site.ssl).toBe(false);
  });

  it('preserves .optional() around a sub-tree (unwrap → recurse → rewrap)', () => {
    const contract = z.object({
      passphrase: z
        .object({
          minimum_length: z.number().optional(),
        })
        .optional(),
    });

    const shape = augment(contract, {
      passphrase: {
        minimum_length: (n) => n.int().min(0).max(256).default(4),
      },
    });

    // Outer optional preserved: omitting passphrase entirely still parses.
    expect(shape.parse({}).passphrase).toBeUndefined();
    // Inner default applies when the block is present.
    expect(shape.parse({ passphrase: {} }).passphrase?.minimum_length).toBe(4);
  });

  it('preserves .nullable() around a sub-tree', () => {
    const contract = z.object({
      block: z.object({ x: z.number().optional() }).nullable(),
    });

    const shape = augment(contract, {
      block: { x: (n) => n.int().default(7) },
    });

    expect(shape.parse({ block: null }).block).toBeNull();
    expect(shape.parse({ block: {} }).block?.x).toBe(7);
  });

  it('recurses through multiple nesting levels', () => {
    const contract = z.object({
      a: z.object({
        b: z.object({
          c: z.boolean().optional(),
        }),
      }),
    });

    const shape = augment(contract, {
      a: { b: { c: (b) => b.default(true) } },
    });

    expect(shape.parse({ a: { b: {} } }).a.b.c).toBe(true);
  });

  it('throws when a sub-tree targets a non-object field', () => {
    const contract = z.object({ port: z.number().optional() });

    expect(() =>
      augment(contract, {
        port: { foo: (n) => n },
      })
    ).toThrow(/not a ZodObject/);
  });
});

describe('augment — runtime unknown-key guard', () => {
  it('throws when a leaf key is not in the contract', () => {
    const contract = z.object({ host: z.string().optional() });
    expect(() =>
      augment(contract, {
        hosts: (s) => s.default('x'), // typo
      })
    ).toThrow(/unknown key "hosts"/);
  });

  it('throws when a sub-tree key is not in the contract', () => {
    const contract = z.object({ site: z.object({ host: z.string().optional() }) });
    expect(() =>
      augment(contract, {
        siteX: { host: (h) => h.default('x') },
      })
    ).toThrow(/unknown key "siteX"/);
  });

  it('includes the known keys in the error message', () => {
    const contract = z.object({ a: z.boolean(), b: z.boolean() });
    expect(() => augment(contract, { c: (s) => s })).toThrow(/known: a, b/);
  });
});

describe('augment — catchall / strict / loose preservation', () => {
  it('preserves an explicit .catchall(...)', () => {
    const contract = z.object({ App: z.string().optional() }).catchall(z.string());

    const shape = augment(contract, { App: (s) => s.default('info') });

    expect(shape.parse({}).App).toBe('info');
    // Catchall still accepts unknown keys.
    const parsed = shape.parse({ Boot: 'debug' }) as Record<string, string>;
    expect(parsed.Boot).toBe('debug');
  });

  it('preserves loose objects (z.looseObject)', () => {
    const contract = z.looseObject({ a: z.string().optional() });
    const shape = augment(contract, { a: (s) => s.default('x') });

    // Loose: unknown keys pass through.
    const parsed = shape.parse({ extra: 42 }) as Record<string, unknown>;
    expect(parsed.a).toBe('x');
    expect(parsed.extra).toBe(42);
  });

  it('preserves strict objects (z.strictObject)', () => {
    const contract = z.strictObject({ a: z.string().optional() });
    const shape = augment(contract, { a: (s) => s.default('x') });

    expect(shape.parse({}).a).toBe('x');
    expect(() => shape.parse({ extra: 42 })).toThrow();
  });
});
