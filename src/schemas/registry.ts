// src/schemas/registry.ts

/**
 * Centralized Schema Registry for JSON Schema Generation
 *
 * Usage:
 *   pnpm run schemas:generate           # Generate all schemas to generated/schemas/
 *   pnpm run schemas:generate:dry-run   # Preview without writing
 *
 * Adding schemas:
 *   1. Import the schema at the top of this file
 *   2. Add to the appropriate category object (shapeSchemas, apiV3Schemas, etc.)
 *   3. Key format: 'category/name' → outputs 'category/name.schema.json'
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────┐
 * │ Zod Schemas (src/schemas/)                              │
 * │   ├── contracts/ → Canonical field definitions           │
 * │   ├── shapes/    → Version-specific wire-format schemas  │
 * │   ├── api/       → API request/response schemas         │
 * │   └── ui/        → Form and UI validation schemas       │
 * ├─────────────────────────────────────────────────────────┤
 * │ Registry (this file)                                    │
 * │   └── Collects schemas with stable identifiers          │
 * ├─────────────────────────────────────────────────────────┤
 * │ Generated JSON Schemas (generated/schemas/)             │
 * │   └── Used by: API docs, forms, external tools, Ruby    │
 * └─────────────────────────────────────────────────────────┘
 *
 * Note on transforms: Schemas using z.transform() (e.g., transforms.fromNumber.toDate)
 * will serialize to their input type (number, string, etc.) in JSON Schema when
 * using io:"input". The transform logic is runtime-only and not representable in JSON Schema.
 */

import { z } from 'zod';

// =============================================================================
// V3 Shape Schemas
// =============================================================================
import { customerSchema } from './shapes/v3/customer';
import { customDomainSchema } from './shapes/v3/custom-domain';
import { secretSchema, secretDetailsSchema } from './shapes/v3/secret';
import { receiptSchema, receiptDetailsSchema, receiptStateSchema } from './shapes/v3/receipt';
import { feedbackSchema } from './shapes/v3/feedback';
import { organizationSchema } from './shapes/organizations/organization';
import { secretStateSchema } from './contracts/secret';

// =============================================================================
// API v3 Schemas
// =============================================================================
import { concealPayloadSchema } from './api/v3/requests/content/conceal';
import { generatePayloadSchema } from './api/v3/requests/content/generate';
import { responseSchemas } from './api/v3/responses';

// =============================================================================
// Schema Categories
// =============================================================================

/**
 * V3 shape schemas - domain entities with V3 wire-format transforms.
 * State enums come from contracts (version-independent).
 */
export const shapeSchemas = {
  'shapes/customer': customerSchema,
  'shapes/secret': secretSchema,
  'shapes/secret-details': secretDetailsSchema,
  'shapes/secret-state': secretStateSchema,
  'shapes/receipt': receiptSchema,
  'shapes/receipt-details': receiptDetailsSchema,
  'shapes/receipt-state': receiptStateSchema,
  'shapes/feedback': feedbackSchema,
  'shapes/custom-domain': customDomainSchema,
  'shapes/organization': organizationSchema,
} as const;

/**
 * API v3 schemas - request/response payloads
 */
export const apiV3Schemas = {
  'api/v3/conceal-payload': concealPayloadSchema,
  'api/v3/generate-payload': generatePayloadSchema,
  'api/v3/secret-response': responseSchemas.secret,
  'api/v3/receipt-response': responseSchemas.receipt,
  'api/v3/conceal-data-response': responseSchemas.concealData,
} as const;

// =============================================================================
// Combined Registry
// =============================================================================

/**
 * All schemas available for JSON Schema generation.
 * Keys are paths relative to the output directory (e.g., 'shapes/customer' -> 'shapes/customer.schema.json')
 */
export const schemaRegistry = {
  ...shapeSchemas,
  ...apiV3Schemas,
} as const;

export type SchemaKey = keyof typeof schemaRegistry;

// =============================================================================
// Registry Utilities
// =============================================================================

/**
 * Get all schema keys organized by category
 */
export function getSchemasByCategory(): Record<string, SchemaKey[]> {
  const categories: Record<string, SchemaKey[]> = {
    shapes: [],
    'api/v3': [],
  };

  for (const key of Object.keys(schemaRegistry) as SchemaKey[]) {
    if (key.startsWith('shapes/')) {
      categories.shapes.push(key);
    } else if (key.startsWith('api/v3/')) {
      categories['api/v3'].push(key);
    }
  }

  return categories;
}

/**
 * Convert a single schema to JSON Schema using Zod v4's native API.
 *
 * Uses `io: "input"` so that schemas with .transform() document the wire
 * format (input type) rather than the coerced application type (output type).
 * For example, `z.number().transform(v => new Date(v * 1000))` produces
 * `{ "type": "number" }` instead of an unrepresentable Date.
 *
 * Note: Schemas using z.preprocess() will serialize to their underlying type.
 * The preprocessing logic (e.g., string-to-boolean conversion) is runtime-only.
 */
export function toJsonSchema(schema: z.ZodType): Record<string, unknown> {
  return z.toJSONSchema(schema, { io: 'input' });
}
