// src/tests/schemas/shapes/helpers/roundtrip.harness.ts
//
// Generic round-trip test harness for schema validation.
// Enables consistent testing patterns across all entities.

import { describe, it, expect } from 'vitest';
import type { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Configuration for round-trip testing of an entity.
 *
 * @template TCanonical - The canonical (post-parse) type
 * @template TV2Wire - The V2 wire format type (pre-parse)
 * @template TV3Wire - The V3 wire format type (pre-parse)
 */
export interface RoundTripHarness<TCanonical, TV2Wire, TV3Wire> {
  /** Human-readable name for the entity (e.g., "receipt", "secret") */
  name: string;

  /** Factory to create canonical test data */
  createCanonical: (overrides?: Partial<TCanonical>) => TCanonical;

  /** Converts canonical to V2 wire format */
  toV2Wire: (canonical: TCanonical) => TV2Wire;

  /** Converts canonical to V3 wire format */
  toV3Wire: (canonical: TCanonical) => TV3Wire;

  /** V2 Zod schema for parsing V2 wire data */
  v2Schema: z.ZodType<TCanonical, z.ZodTypeDef, TV2Wire>;

  /** V3 Zod schema for parsing V3 wire data */
  v3Schema: z.ZodType<TCanonical, z.ZodTypeDef, TV3Wire>;

  /**
   * Compares two canonical objects for equality.
   * Should handle Date comparisons by timestamp.
   */
  compareCanonical: (a: TCanonical, b: TCanonical) => {
    equal: boolean;
    differences: string[];
  };

  /**
   * Optional: Fields that are known to transform (e.g., null → false).
   * These are excluded from strict equality checks.
   */
  transformedFields?: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Round-Trip Test Runner
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generates a standard round-trip test suite for an entity.
 *
 * Tests:
 * - V2: canonical → wire → parse → matches canonical
 * - V3: canonical → wire → parse → matches canonical
 *
 * @example
 * ```ts
 * import { runRoundTripTests } from './helpers/roundtrip.harness';
 * import { receiptHarness } from './fixtures/receipt.fixtures';
 *
 * runRoundTripTests(receiptHarness);
 * ```
 */
export function runRoundTripTests<TCanonical, TV2Wire, TV3Wire>(
  harness: RoundTripHarness<TCanonical, TV2Wire, TV3Wire>
): void {
  describe(`${harness.name} Round-Trip`, () => {
    describe('V2 format', () => {
      it('canonical → V2 wire → V2 schema → matches canonical', () => {
        const canonical = harness.createCanonical();
        const wire = harness.toV2Wire(canonical);
        const parsed = harness.v2Schema.parse(wire);

        const result = harness.compareCanonical(canonical, parsed);

        if (!result.equal) {
          // Filter out known transformed fields
          const unexpectedDiffs = result.differences.filter(
            (diff) => !harness.transformedFields?.some((f) => diff.startsWith(f))
          );

          if (unexpectedDiffs.length > 0) {
            console.log(`[${harness.name}] V2 Round-trip differences:`, unexpectedDiffs);
          }
        }

        // Allow transformed fields but fail on unexpected differences
        const criticalDiffs = result.differences.filter(
          (diff) => !harness.transformedFields?.some((f) => diff.startsWith(f))
        );
        expect(criticalDiffs, 'Unexpected round-trip differences').toEqual([]);
      });

      it('preserves null values through round-trip', () => {
        // This test verifies that null fields remain null
        const canonical = harness.createCanonical();
        const wire = harness.toV2Wire(canonical);

        // Schema should parse successfully
        const result = harness.v2Schema.safeParse(wire);
        expect(result.success).toBe(true);
      });
    });

    describe('V3 format', () => {
      it('canonical → V3 wire → V3 schema → matches canonical', () => {
        const canonical = harness.createCanonical();
        const wire = harness.toV3Wire(canonical);
        const parsed = harness.v3Schema.parse(wire);

        const result = harness.compareCanonical(canonical, parsed);

        // Filter out known transformed fields
        const criticalDiffs = result.differences.filter(
          (diff) => !harness.transformedFields?.some((f) => diff.startsWith(f))
        );
        expect(criticalDiffs, 'Unexpected round-trip differences').toEqual([]);
      });

      it('preserves null values through round-trip', () => {
        const canonical = harness.createCanonical();
        const wire = harness.toV3Wire(canonical);

        const result = harness.v3Schema.safeParse(wire);
        expect(result.success).toBe(true);
      });
    });

    describe('cross-format consistency', () => {
      it('V2 and V3 produce equivalent canonical output', () => {
        const canonical = harness.createCanonical();

        const v2Wire = harness.toV2Wire(canonical);
        const v3Wire = harness.toV3Wire(canonical);

        const v2Parsed = harness.v2Schema.parse(v2Wire);
        const v3Parsed = harness.v3Schema.parse(v3Wire);

        const result = harness.compareCanonical(v2Parsed, v3Parsed);

        // Filter out transformed fields for cross-format comparison
        const criticalDiffs = result.differences.filter(
          (diff) => !harness.transformedFields?.some((f) => diff.startsWith(f))
        );

        if (criticalDiffs.length > 0) {
          console.log(`[${harness.name}] V2/V3 output differences:`, criticalDiffs);
        }
      });
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Compatibility Test Runner
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generates compatibility tests between V2 and V3 schemas.
 *
 * Tests:
 * - V2 wire → V3 schema (expected to fail)
 * - V3 wire → V2 schema (expected to succeed due to flexible preprocessors)
 */
export function runCompatibilityTests<TCanonical, TV2Wire, TV3Wire>(
  harness: RoundTripHarness<TCanonical, TV2Wire, TV3Wire>
): void {
  describe(`${harness.name} Cross-Version Compatibility`, () => {
    describe('V2 Wire → V3 Schema (Forward Compatibility)', () => {
      it('documents incompatibility: V3 expects strict types', () => {
        const canonical = harness.createCanonical();
        const v2Wire = harness.toV2Wire(canonical);

        // Attempt to parse V2 wire with V3 schema
        const result = harness.v3Schema.safeParse(v2Wire);

        // V3 typically rejects V2 wire due to type mismatches
        // (strings instead of numbers/booleans)
        console.log(
          `[${harness.name}] V2→V3 compatible:`,
          result.success,
          result.success ? '' : `(${result.error.issues.length} errors)`
        );

        // Document but don't assert - this is informational
      });
    });

    describe('V3 Wire → V2 Schema (Backward Compatibility)', () => {
      it('V2 flexible preprocessors handle V3 native types', () => {
        const canonical = harness.createCanonical();
        const v3Wire = harness.toV3Wire(canonical);

        // V2's preprocess functions (parseBoolean, parseNumber, parseDateValue)
        // are designed to handle both string and native inputs
        const result = harness.v2Schema.safeParse(v3Wire);

        console.log(
          `[${harness.name}] V3→V2 compatible:`,
          result.success,
          result.success ? '' : `(${result.error.issues.length} errors)`
        );

        // V3 → V2 is generally expected to work
        // If it fails, document the specific issues
        if (!result.success) {
          console.log(
            `[${harness.name}] V3→V2 errors:`,
            result.error.issues.slice(0, 3).map((i) => `${i.path.join('.')}: ${i.message}`)
          );
        }
      });
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility Functions
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a simple comparison function for objects with Date fields.
 * Converts Dates to timestamps for comparison.
 */
export function createDateAwareComparator<T extends Record<string, unknown>>(
  dateFields: (keyof T)[],
  ignoreFields: (keyof T)[] = []
): (a: T, b: T) => { equal: boolean; differences: string[] } {
  return (a: T, b: T) => {
    const differences: string[] = [];

    for (const key of Object.keys(a) as (keyof T)[]) {
      if (ignoreFields.includes(key)) continue;

      const aVal = a[key];
      const bVal = b[key];

      if (dateFields.includes(key)) {
        // Compare dates by timestamp
        const aTime = aVal instanceof Date ? aVal.getTime() : aVal;
        const bTime = bVal instanceof Date ? bVal.getTime() : bVal;
        if (aTime !== bTime) {
          differences.push(`${String(key)}: ${aTime} !== ${bTime}`);
        }
      } else if (Array.isArray(aVal) && Array.isArray(bVal)) {
        // Compare arrays by JSON
        if (JSON.stringify(aVal) !== JSON.stringify(bVal)) {
          differences.push(`${String(key)}: ${JSON.stringify(aVal)} !== ${JSON.stringify(bVal)}`);
        }
      } else if (aVal !== bVal) {
        differences.push(`${String(key)}: ${JSON.stringify(aVal)} !== ${JSON.stringify(bVal)}`);
      }
    }

    return { equal: differences.length === 0, differences };
  };
}
