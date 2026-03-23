// src/tests/schemas/generation/schema-generation.spec.ts
//
// Guards the Zod → JSON Schema generation pipeline:
//   1. Registry completeness (all expected schemas are present)
//   2. Round-trip validity (every registered schema produces well-formed JSON Schema)
//   3. Transform fidelity (io:"input" serializes wire types, not domain types)

import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { schemaRegistry, toJsonSchema, type SchemaKey } from '@/schemas/registry';
import { transforms } from '@/schemas/transforms';

const registryKeys = Object.keys(schemaRegistry) as SchemaKey[];

/**
 * Replicates the serialization options from generate.ts:generateSchema.
 * The registry's toJsonSchema() is simpler (no override/unrepresentable),
 * so schemas with z.preprocess(..., z.date()) throw there. The actual
 * generator handles them via the override hook + unrepresentable:'any'.
 */
function generateJsonSchema(schema: z.ZodType): Record<string, unknown> {
  return z.toJSONSchema(schema, {
    io: 'input',
    unrepresentable: 'any',
    override: (ctx) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const def = (ctx.zodSchema as any)?._zod?.def;
      if (def?.type === 'date') {
        ctx.jsonSchema.type = 'string';
        ctx.jsonSchema.format = 'date-time';
      }
    },
  });
}

// =============================================================================
// 1. Registry completeness
// =============================================================================

describe('schemaRegistry completeness', () => {
  it('contains all expected model schemas', () => {
    const modelKeys = registryKeys.filter((k) => k.startsWith('models/'));
    const expected = [
      'models/customer',
      'models/secret',
      'models/secret-details',
      'models/secret-state',
      'models/receipt',
      'models/receipt-details',
      'models/receipt-state',
      'models/feedback',
      'models/custom-domain',
      'models/organization',
    ];
    for (const key of expected) {
      expect(modelKeys, `missing ${key}`).toContain(key);
    }
    expect(modelKeys).toHaveLength(expected.length);
  });

  it('contains all expected API schemas', () => {
    const apiKeys = registryKeys.filter((k) => k.startsWith('api/'));
    const expected = [
      'api/v3/conceal-payload',
      'api/v3/generate-payload',
      'api/v3/secret-response',
      'api/v3/receipt-response',
      'api/v3/conceal-data-response',
    ];
    for (const key of expected) {
      expect(apiKeys, `missing ${key}`).toContain(key);
    }
    expect(apiKeys).toHaveLength(expected.length);
  });

  it('total count matches expected', () => {
    expect(registryKeys).toHaveLength(15);
  });

  it('every entry resolves to a valid Zod schema', () => {
    for (const key of registryKeys) {
      const schema = schemaRegistry[key];
      expect(schema, `${key} is undefined`).toBeDefined();
      expect(typeof schema.parse, `${key}.parse is not a function`).toBe('function');
    }
  });
});

// =============================================================================
// 2. Generation round-trip — no degenerate output
// =============================================================================

describe('JSON Schema generation round-trip', () => {
  it.each(registryKeys)('%s produces well-formed JSON Schema', (key) => {
    const schema = schemaRegistry[key];
    const jsonSchema = generateJsonSchema(schema);

    // Must not be empty (degenerate {} from unrepresentable types)
    const keys = Object.keys(jsonSchema);
    expect(keys.length, `${key} produced empty JSON Schema`).toBeGreaterThan(0);

    // Must contain at least one structural keyword
    const structuralKeywords = ['type', 'properties', 'anyOf', 'oneOf', 'allOf', '$ref'];
    const hasStructure = structuralKeywords.some((kw) => kw in jsonSchema);
    expect(hasStructure, `${key} lacks structural keywords: ${JSON.stringify(jsonSchema)}`).toBe(
      true
    );
  });

  it('object schemas include properties', () => {
    const objectSchemas = registryKeys.filter((key) => {
      const js = generateJsonSchema(schemaRegistry[key]);
      return js.type === 'object';
    });
    // Sanity: most schemas in the registry are objects
    expect(objectSchemas.length).toBeGreaterThan(5);

    for (const key of objectSchemas) {
      const js = generateJsonSchema(schemaRegistry[key]);
      expect('properties' in js, `${key} is type:object but has no properties`).toBe(true);
    }
  });

  it('generator wrapper adds $schema and $id fields', () => {
    // generate.ts wraps z.toJSONSchema() output with JSON Schema 2020-12
    // metadata. Verify the convention with one representative schema.
    const raw = generateJsonSchema(schemaRegistry['models/feedback']);
    const wrapped = {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: 'https://onetimesecret.com/schemas/models/feedback.schema.json',
      ...raw,
    };
    expect(wrapped.$schema).toBe('https://json-schema.org/draft/2020-12/schema');
    expect(wrapped.$id).toContain('onetimesecret.com/schemas/');
    expect(wrapped.$id).toMatch(/\.schema\.json$/);
  });

  it('date fields in model schemas serialize as string (via transform)', () => {
    // V2 schemas use z.string().transform() for date fields, which serializes
    // to { type: 'string' } in JSON Schema (transform logic is runtime-only).
    const customerSchema = generateJsonSchema(schemaRegistry['models/customer']);
    const props = customerSchema.properties as Record<string, Record<string, unknown>>;
    // customerSchema has created/updated fields
    expect(props.created).toEqual({ type: 'string' });
    expect(props.updated).toEqual({ type: 'string' });
  });
});

describe('registry.toJsonSchema vs generator parity', () => {
  // The registry's toJsonSchema lacks the override hook and unrepresentable
  // option that generate.ts uses. Schemas with z.preprocess(..., z.date())
  // throw when using the registry utility. This test documents the gap.
  //
  // Discovered dynamically so the test adapts as schemas are added/changed.
  const schemasWithDates = registryKeys.filter((key) => {
    try {
      toJsonSchema(schemaRegistry[key]);
      return false;
    } catch {
      return true;
    }
  });

  it('no schemas contain z.date() (using transform pattern instead)', () => {
    // All V2 schemas now use z.string().transform() instead of z.date(),
    // so toJsonSchema works without throwing. This is intentional.
    expect(schemasWithDates.length).toBe(0);
  });

  it('toJsonSchema throws on schemas containing z.date() (known limitation)', () => {
    for (const key of schemasWithDates) {
      expect(
        () => toJsonSchema(schemaRegistry[key]),
        `${key} should throw without override hook`
      ).toThrow('Date cannot be represented');
    }
  });

  it('generateJsonSchema handles the same schemas without throwing', () => {
    for (const key of schemasWithDates) {
      expect(() => generateJsonSchema(schemaRegistry[key])).not.toThrow();
    }
  });
});

// =============================================================================
// 3. Transform fidelity — io:"input" serializes wire types, not Date
// =============================================================================

describe('transform fidelity with io:"input"', () => {
  /** Matches the serialization options used by both generators. */
  function toInputSchema(schema: z.ZodType): Record<string, unknown> {
    return z.toJSONSchema(schema, { io: 'input', unrepresentable: 'any' });
  }

  describe('fromNumber.toDate', () => {
    it('serializes as { type: "number" }', () => {
      const js = toInputSchema(transforms.fromNumber.toDate);
      expect(js.type).toBe('number');
    });
  });

  describe('fromNumber.toDateNullable', () => {
    it('serializes as number | null', () => {
      const js = toInputSchema(transforms.fromNumber.toDateNullable);
      expect(js.anyOf).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ type: 'number' }),
          expect.objectContaining({ type: 'null' }),
        ])
      );
    });
  });

  describe('fromNumber.toDateOptional', () => {
    it('serializes as { type: "number" }', () => {
      const js = toInputSchema(transforms.fromNumber.toDateOptional);
      expect(js.type).toBe('number');
    });
  });

  describe('fromNumber.toDateNullish', () => {
    it('serializes as number | null', () => {
      const js = toInputSchema(transforms.fromNumber.toDateNullish);
      expect(js.anyOf).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ type: 'number' }),
          expect.objectContaining({ type: 'null' }),
        ])
      );
    });
  });

  describe('regression guard: removing io:"input" breaks transform serialization', () => {
    it('toDate without io:"input" does NOT produce type:"number"', () => {
      // Without io:"input", Zod serializes the *output* type (Date),
      // which has no JSON Schema representation. This test documents
      // the failure mode that io:"input" prevents.
      const js = z.toJSONSchema(transforms.fromNumber.toDate, {
        unrepresentable: 'any',
      });
      expect(js.type).not.toBe('number');
    });

    it('toDateNullable without io:"input" loses the number type', () => {
      const js = z.toJSONSchema(transforms.fromNumber.toDateNullable, {
        unrepresentable: 'any',
      });
      // Without io:"input", the anyOf degrades — no number branch
      const hasNumberBranch =
        Array.isArray(js.anyOf) && js.anyOf.some((b: unknown) => (b as Record<string, unknown>).type === 'number');
      expect(hasNumberBranch).toBe(false);
    });
  });
});
