// src/schemas/config/billing.ts

/**
 * Billing Configuration Schema
 *
 * Zod v4 schema for etc/billing/billing.yaml
 *
 * Purpose:
 * - Type-safe validation of billing configuration
 * - Runtime validation for YAML parsing
 * - TypeScript type inference for billing config usage
 * - Entitlement definitions (system-wide features)
 *
 * Usage:
 * ```typescript
 * import { BillingConfigSchema, type BillingConfig } from '@/schemas/config/billing';
 *
 * const config = BillingConfigSchema.parse(yamlData);
 * const canUseDomains = config.billing.entitlements.custom_domains;
 * ```
 */

import { z } from 'zod/v4';

/**
 * Entitlement Category
 * Groups entitlements by functional area
 */
export const EntitlementCategorySchema = z.enum([
  'core',
  'collaboration',
  'infrastructure',
  'branding',
  'advanced',
  'support',
]);

export type EntitlementCategory = z.infer<typeof EntitlementCategorySchema>;

/**
 * Entitlement Definition
 * Describes a single billing entitlement/feature
 */
export const EntitlementDefinitionSchema = z.object({
  category: EntitlementCategorySchema,
  description: z.string().min(1),
});

export type EntitlementDefinition = z.infer<typeof EntitlementDefinitionSchema>;

/**
 * Billing Configuration Root
 * Complete billing.yaml structure
 */
export const BillingConfigSchema = z.object({
  billing: z.object({
    enabled: z.boolean().describe('Whether billing is enabled'),
    stripe_key: z.string().min(1).describe('Stripe API key'),
    webhook_signing_secret: z.string().min(1).describe('Stripe webhook signing secret'),
    stripe_api_version: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}\.\w+$/, 'Must match format: YYYY-MM-DD.version')
      .describe('Stripe API version (e.g., 2025-11-20.clover)'),

    entitlements: z.record(
      z.string(),
      EntitlementDefinitionSchema,
    ).describe('System-wide entitlement definitions'),
  }),
});

export type BillingConfig = z.infer<typeof BillingConfigSchema>;

/**
 * Entitlement ID Type
 * Type-safe entitlement identifiers from config
 */
export type EntitlementId = keyof BillingConfig['billing']['entitlements'];

/**
 * Helper: Get entitlement by ID
 *
 * @param config - Validated billing config
 * @param entitlementId - Entitlement identifier
 * @returns Entitlement definition or undefined
 */
export function getEntitlementById(
  config: BillingConfig,
  entitlementId: string,
): EntitlementDefinition | undefined {
  return config.billing.entitlements[entitlementId];
}

/**
 * Helper: Get entitlements by category
 *
 * @param config - Validated billing config
 * @param category - Entitlement category to filter by
 * @returns Array of [entitlementId, entitlement] tuples
 */
export function getEntitlementsByCategory(
  config: BillingConfig,
  category: EntitlementCategory,
): Array<[string, EntitlementDefinition]> {
  return Object.entries(config.billing.entitlements)
    .filter(([, cap]) => cap.category === category);
}

/**
 * Helper: Check if entitlement exists
 *
 * @param config - Validated billing config
 * @param entitlementId - Entitlement ID to check
 * @returns True if entitlement is defined
 */
export function hasEntitlement(
  config: BillingConfig,
  entitlementId: string,
): boolean {
  return entitlementId in config.billing.entitlements;
}

/**
 * Helper: Get all entitlement IDs
 *
 * @param config - Validated billing config
 * @returns Array of entitlement IDs
 */
export function getAllEntitlementIds(config: BillingConfig): string[] {
  return Object.keys(config.billing.entitlements);
}

/**
 * Type guard: Check if config is valid
 *
 * @param data - Unknown data to validate
 * @returns True if data matches BillingConfig schema
 */
export function isBillingConfig(data: unknown): data is BillingConfig {
  return BillingConfigSchema.safeParse(data).success;
}
