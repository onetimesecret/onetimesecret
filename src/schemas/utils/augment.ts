// src/schemas/utils/augment.ts

/**
 * augment — apply defaults and value constraints to a Zod object contract
 * without restating the contract's structure.
 *
 * The config layer keeps type-only contracts in `contracts/config/` and
 * runtime-augmented shapes in `shapes/config/`. Without this helper the
 * shape files end up restating every field name from the contract — the
 * moment a default belongs inside a nested object, plain `.extend()`
 * forces a full re-declaration of that object's siblings. `augment`
 * walks the contract tree and applies overrides only where the shape
 * tree provides them; everything else passes through verbatim.
 *
 * Usage:
 *
 * ```ts
 * const siteShape = augment(siteSchema, {
 *   host: (h) => h.default('localhost:3000'),
 *   ssl: (s) => s.default(false),
 *   secret_options: {
 *     passphrase: {
 *       minimum_length: (n) => n.int().min(0).max(256).default(4),
 *     },
 *   },
 * });
 * ```
 *
 * Conventions:
 * - **Leaf** entries `(field) => field.someChain()` transform a single
 *   field. The field is unwrapped from `.optional()` / `.nullable()` /
 *   `.default()` before being handed to the leaf, so `n.int().min(...)`
 *   works on a contract field declared as `z.number().optional()`. The
 *   leaf's return value replaces the field as-is (the helper does NOT
 *   auto-re-wrap). If you want to preserve a wrapper, re-apply it in the
 *   leaf: `(s) => s.nullable().default('x')`.
 * - **Sub-tree** entries recurse into a nested `ZodObject`. The helper
 *   transparently unwraps wrappers, recurses, and re-wraps in the
 *   original order so a `secret_options: z.object({...}).optional()`
 *   field stays optional after augmentation.
 * - Fields not mentioned in the tree pass through unchanged.
 * - Object-level qualifiers — `.catchall(...)`, `z.strictObject`,
 *   `z.looseObject` — are preserved via the contract's `def.catchall`.
 * - **Unknown keys throw** at construction time so a typo surfaces on
 *   the next test run instead of silently doing nothing.
 *
 * Type note: the leaf parameter is intentionally `any`. TypeScript can't
 * narrow it across the tree boundary (the contract's `.shape` is a
 * heterogeneous record), and a typed-tree variant would require recursive
 * conditional generics for marginal value over the runtime key guard.
 * The leaf body is written against the field the contract declares — if
 * you mis-chain a method, TypeScript will catch it inside the leaf.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

import { z } from 'zod';

export type LeafTransform = (field: any) => z.ZodType;
export type AugmentTree = { [key: string]: LeafTransform | AugmentTree };

const WRAPPER_TYPES = new Set(['optional', 'nullable', 'default']);

interface UnwrapResult {
  inner: any;
  rewrap: (next: any) => any;
}

function unwrap(schema: any): UnwrapResult {
  const rebuilders: Array<(s: any) => any> = [];
  let current: any = schema;

  while (current && WRAPPER_TYPES.has(current.def?.type)) {
    const def = current.def;
    switch (def.type) {
      case 'optional':
        rebuilders.push((s) => s.optional());
        break;
      case 'nullable':
        rebuilders.push((s) => s.nullable());
        break;
      case 'default': {
        const defaultValue = def.defaultValue;
        rebuilders.push((s) => s.default(defaultValue));
        break;
      }
    }
    current = def.innerType;
  }

  return {
    inner: current,
    // Re-apply wrappers innermost-first so the outer order matches the input.
    rewrap: (next) => rebuilders.reduceRight((acc, w) => w(acc), next),
  };
}

export function augment<T extends z.ZodObject<z.ZodRawShape>>(
  contract: T,
  tree: AugmentTree
): T {
  for (const key of Object.keys(tree)) {
    if (!(key in contract.shape)) {
      const known = Object.keys(contract.shape).join(', ');
      throw new Error(
        `augment: unknown key "${key}" not in contract shape (known: ${known})`
      );
    }
  }

  const nextShape: Record<string, any> = { ...contract.shape };

  for (const [key, override] of Object.entries(tree)) {
    const field = (contract.shape as Record<string, any>)[key];
    if (typeof override === 'function') {
      const { inner } = unwrap(field);
      nextShape[key] = override(inner);
    } else {
      const { inner, rewrap } = unwrap(field);
      if (!(inner instanceof z.ZodObject)) {
        const seen = inner?.def?.type ?? typeof inner;
        throw new Error(
          `augment: sub-tree provided for "${key}", but underlying field is not a ZodObject (got ${seen})`
        );
      }
      nextShape[key] = rewrap(augment(inner, override));
    }
  }

  let next: any = z.object(nextShape);
  const catchall = (contract as any).def?.catchall;
  if (catchall) {
    next = next.catchall(catchall);
  }
  return next as T;
}
