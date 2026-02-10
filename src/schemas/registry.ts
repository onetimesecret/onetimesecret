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
 *   2. Add to the appropriate category object (modelSchemas, apiV3Schemas, etc.)
 *   3. Key format: 'category/name' → outputs 'category/name.schema.json'
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────┐
 * │ Zod Schemas (src/schemas/)                              │
 * │   ├── models/    → Core domain models                   │
 * │   ├── api/       → API request/response schemas         │
 * │   ├── config/    → Configuration schemas                │
 * │   └── ui/        → Form and UI validation schemas       │
 * ├─────────────────────────────────────────────────────────┤
 * │ Registry (this file)                                    │
 * │   └── Collects schemas with stable identifiers          │
 * ├─────────────────────────────────────────────────────────┤
 * │ Generated JSON Schemas (generated/schemas/)             │
 * │   └── Used by: API docs, forms, external tools, Ruby    │
 * └─────────────────────────────────────────────────────────┘
 *
 * Note on transforms: Schemas using z.preprocess() (e.g., transforms.fromString.boolean)
 * will serialize to their underlying type (boolean, number, etc.) in JSON Schema.
 * The preprocessing logic is runtime-only and not representable in JSON Schema.
 */

import { z } from 'zod';

// =============================================================================
// Model Schemas
// =============================================================================
import { customerSchema } from './models/customer';
import { secretSchema, secretDetailsSchema, secretStateSchema } from './models/secret';
import { receiptSchema, receiptDetailsSchema, receiptStateSchema } from './models/receipt';
import { feedbackSchema } from './models/feedback';

// =============================================================================
// API v3 Schemas
// =============================================================================
import { concealPayloadSchema } from './api/v3/payloads/conceal';
import { generatePayloadSchema } from './api/v3/payloads/generate';
import { responseSchemas } from './api/v3/responses';

// =============================================================================
// Billing Schemas
// =============================================================================
import {
  BillingCatalogSchema,
  PlanDefinitionSchema,
  EntitlementDefinitionSchema,
} from './config/billing';

// =============================================================================
// Config Schemas
// =============================================================================
import {
  staticConfigSchema,
  mutableConfigSchema,
  runtimeConfigSchema,
} from './config/config';
import { authConfigSchema } from './config/auth';
import { loggingConfigSchema } from './config/logging';

// =============================================================================
// Schema Categories
// =============================================================================

/**
 * Core model schemas - domain entities
 */
export const modelSchemas = {
  'models/customer': customerSchema,
  'models/secret': secretSchema,
  'models/secret-details': secretDetailsSchema,
  'models/secret-state': secretStateSchema,
  'models/receipt': receiptSchema,
  'models/receipt-details': receiptDetailsSchema,
  'models/receipt-state': receiptStateSchema,
  'models/feedback': feedbackSchema,
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

/**
 * Billing schemas - catalog and component definitions
 */
export const billingSchemas = {
  'billing/catalog': BillingCatalogSchema,
  'billing/plan-definition': PlanDefinitionSchema,
  'billing/entitlement-definition': EntitlementDefinitionSchema,
} as const;

/**
 * Config schemas - application configuration files
 */
export const configSchemas = {
  'config/static': staticConfigSchema,
  'config/mutable': mutableConfigSchema,
  'config/runtime': runtimeConfigSchema,
  'config/auth': authConfigSchema,
  'config/logging': loggingConfigSchema,
} as const;

// =============================================================================
// Combined Registry
// =============================================================================

/**
 * All schemas available for JSON Schema generation.
 * Keys are paths relative to the output directory (e.g., 'models/customer' -> 'models/customer.schema.json')
 */
export const schemaRegistry = {
  ...modelSchemas,
  ...apiV3Schemas,
  ...billingSchemas,
  ...configSchemas,
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
    models: [],
    'api/v3': [],
    billing: [],
    config: [],
  };

  for (const key of Object.keys(schemaRegistry) as SchemaKey[]) {
    if (key.startsWith('models/')) {
      categories.models.push(key);
    } else if (key.startsWith('api/v3/')) {
      categories['api/v3'].push(key);
    } else if (key.startsWith('billing/')) {
      categories.billing.push(key);
    } else if (key.startsWith('config/')) {
      categories.config.push(key);
    }
  }

  return categories;
}

/**
 * Convert a single schema to JSON Schema using Zod v4's native API.
 *
 * Note: Schemas using z.preprocess() will serialize to their underlying type.
 * The preprocessing logic (e.g., string-to-boolean conversion) is runtime-only.
 */
export function toJsonSchema(schema: z.ZodType): Record<string, unknown> {
  return z.toJSONSchema(schema);
}
