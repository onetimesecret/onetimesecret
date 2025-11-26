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
 * - Capability definitions (system-wide features)
 *
 * Usage:
 * ```typescript
 * import { BillingConfigSchema, type BillingConfig } from '@/schemas/config/billing';
 *
 * const config = BillingConfigSchema.parse(yamlData);
 * const canUseDomains = config.billing.capabilities.custom_domains;
 * ```
 */

import { z } from 'zod/v4';

/**
 * Capability Category
 * Groups capabilities by functional area
 */
export const CapabilityCategorySchema = z.enum([
  'core',
  'collaboration',
  'infrastructure',
  'branding',
  'advanced',
  'support',
]);

export type CapabilityCategory = z.infer<typeof CapabilityCategorySchema>;

/**
 * Capability Definition
 * Describes a single billing capability/feature
 */
export const CapabilityDefinitionSchema = z.object({
  category: CapabilityCategorySchema,
  description: z.string().min(1),
});

export type CapabilityDefinition = z.infer<typeof CapabilityDefinitionSchema>;

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

    capabilities: z.record(
      z.string(),
      CapabilityDefinitionSchema,
    ).describe('System-wide capability definitions'),
  }),
});

export type BillingConfig = z.infer<typeof BillingConfigSchema>;

/**
 * Capability ID Type
 * Type-safe capability identifiers from config
 */
export type CapabilityId = keyof BillingConfig['billing']['capabilities'];

/**
 * Helper: Get capability by ID
 *
 * @param config - Validated billing config
 * @param capabilityId - Capability identifier
 * @returns Capability definition or undefined
 */
export function getCapabilityById(
  config: BillingConfig,
  capabilityId: string,
): CapabilityDefinition | undefined {
  return config.billing.capabilities[capabilityId];
}

/**
 * Helper: Get capabilities by category
 *
 * @param config - Validated billing config
 * @param category - Capability category to filter by
 * @returns Array of [capabilityId, capability] tuples
 */
export function getCapabilitiesByCategory(
  config: BillingConfig,
  category: CapabilityCategory,
): Array<[string, CapabilityDefinition]> {
  return Object.entries(config.billing.capabilities)
    .filter(([, cap]) => cap.category === category);
}

/**
 * Helper: Check if capability exists
 *
 * @param config - Validated billing config
 * @param capabilityId - Capability ID to check
 * @returns True if capability is defined
 */
export function hasCapability(
  config: BillingConfig,
  capabilityId: string,
): boolean {
  return capabilityId in config.billing.capabilities;
}

/**
 * Helper: Get all capability IDs
 *
 * @param config - Validated billing config
 * @returns Array of capability IDs
 */
export function getAllCapabilityIds(config: BillingConfig): string[] {
  return Object.keys(config.billing.capabilities);
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
