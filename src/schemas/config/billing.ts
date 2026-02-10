// src/schemas/config/billing.ts

/**
 * Billing Configuration Schema
 *
 * Zod v4 schema for etc/billing.yaml (unified flat-structure configuration)
 *
 * Purpose:
 * - Type-safe validation of billing configuration
 * - Runtime validation for YAML parsing
 * - TypeScript type inference for billing config usage
 * - Entitlement definitions (system-wide features)
 * - Plan catalog definitions (active and legacy plans)
 *
 * Usage:
 * ```typescript
 * import { BillingConfigSchema, type BillingConfig } from '@/schemas/config/billing';
 *
 * const config = BillingConfigSchema.parse(yamlData);
 * const canUseDomains = config.entitlements.custom_domains;
 * const identityPlan = config.plans.identity_plus_v1;
 * ```
 */

import { z } from 'zod';

// =============================================================================
// Constants
// =============================================================================

/**
 * Schema Version
 * Must match schema_version in billing.yaml
 */
export const CATALOG_SCHEMA_VERSION = '1.0';

// =============================================================================
// Entitlement Schemas
// =============================================================================

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

// =============================================================================
// Plan Component Schemas
// =============================================================================

/**
 * Billing Tier
 * Hierarchical plan tiers
 */
export const BillingTierSchema = z.enum(['free', 'single_account', 'single_team', 'multi_team']);

export type BillingTier = z.infer<typeof BillingTierSchema>;

/**
 * Tenancy Type
 * Infrastructure isolation level
 */
export const TenancyTypeSchema = z.enum([
  'multi', // Multi-tenant shared infrastructure
  'dedicated', // Single-tenant dedicated infrastructure
]);

export type TenancyType = z.infer<typeof TenancyTypeSchema>;

/**
 * Billing Interval
 * Subscription billing frequency
 */
export const BillingIntervalSchema = z.enum(['month', 'year']);

export type BillingInterval = z.infer<typeof BillingIntervalSchema>;

/**
 * Currency Code
 * ISO 4217 currency codes
 */
export const CurrencyCodeSchema = z.enum(['cad', 'eur', 'cad', 'nzd']);

export type CurrencyCode = z.infer<typeof CurrencyCodeSchema>;

/**
 * Limit Value
 * Resource limits (-1 = unlimited, null = TBD, positive integer = specific limit)
 */
export const LimitValueSchema = z.union([
  z.literal(-1).describe('Unlimited'),
  z.number().int().positive().describe('Specific limit'),
  z.null().describe('To be determined'),
]);

export type LimitValue = z.infer<typeof LimitValueSchema>;

/**
 * Plan Limits
 * Resource constraints for a billing plan
 */
export const PlanLimitsSchema = z.object({
  organizations: LimitValueSchema.describe('Maximum number of organizations'),
  members_per_team: LimitValueSchema.describe('Maximum members per team'),
  custom_domains: LimitValueSchema.describe('Maximum custom domains'),
  secret_lifetime: LimitValueSchema.describe('Maximum secret lifetime in seconds'),
  secrets_per_day: LimitValueSchema.optional().describe('Daily secret creation limit'),
});

export type PlanLimits = z.infer<typeof PlanLimitsSchema>;

/**
 * Plan Price
 * Stripe price configuration for a billing interval
 */
export const PlanPriceSchema = z.object({
  interval: BillingIntervalSchema,
  amount: z.number().int().nonnegative().describe('Amount in cents (e.g., 2900 = $29.00)'),
  currency: CurrencyCodeSchema,
});

export type PlanPrice = z.infer<typeof PlanPriceSchema>;

/**
 * Plan Definition
 * Complete billing plan configuration
 *
 * Note: tier is optional to allow incomplete/draft plans in catalog.
 * - Free tier plans (tier: 'free') are not created in Stripe
 * - Nil/missing tier plans are skipped with warnings (incomplete definitions)
 * - All other tiers require Stripe product creation
 */
export const PlanDefinitionSchema = z.object({
  name: z.string().min(1).describe('Display name for the plan'),
  tier: BillingTierSchema.optional().describe('Billing tier (optional for draft plans)'),
  tenancy: TenancyTypeSchema.optional().describe('Tenancy type (optional for draft plans)'),
  region: z.string().optional().nullable().describe('Region identifier for composite matching (e.g., EU, US, CA)'),
  stripe_product_id: z
    .string()
    .regex(/^prod_/)
    .nullable()
    .optional()
    .describe('Direct Stripe product ID binding (escape hatch for matching issues)'),
  plan_name_label: z.string().optional().describe('i18n key for plan category label'),
  display_order: z
    .number()
    .int()
    .nullable()
    .describe('Sort order on plans page (higher = earlier, null = hidden)'),
  show_on_plans_page: z.boolean().describe('Visibility on public plans page'),
  includes_plan: z
    .string()
    .optional()
    .describe('Plan ID this plan includes (for "Includes everything in X" display)'),
  description: z.string().min(1).optional().describe('Plan description for documentation'),
  legacy: z.boolean().optional().describe('Marks plan as legacy/grandfathered (no longer offered)'),
  grandfathered_until: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe('ISO date until which plan is grandfathered (YYYY-MM-DD)'),

  entitlements: z.array(z.string().min(1)).describe('Array of entitlement IDs'),
  features: z
    .array(z.string().min(1))
    .optional()
    .describe('Array of i18n feature keys for UI display'),
  limits: PlanLimitsSchema,
  prices: z.array(PlanPriceSchema).nullable().describe('Available pricing options'),
});

export type PlanDefinition = z.infer<typeof PlanDefinitionSchema>;

/**
 * Stripe Metadata Field Definition
 *
 * In billing.yaml, metadata fields are arrays of single-key objects:
 *   required:
 *     - app: "onetimesecret"
 *     - tier: "Tier identifier..."
 *
 * This parses as [{app: "onetimesecret"}, {tier: "..."}] in JS,
 * so each element is a record with one key-value pair.
 */
export const MetadataFieldSchema = z.array(
  z.record(z.string(), z.string().describe('Field description or example value'))
);

/**
 * Stripe Metadata Schema Definition
 */
export const StripeMetadataSchemaDefinition = z.object({
  required: MetadataFieldSchema.describe('Required metadata fields'),
  optional: MetadataFieldSchema.optional().describe('Optional metadata fields'),
});

export type StripeMetadataSchema = z.infer<typeof StripeMetadataSchemaDefinition>;

// =============================================================================
// Root Configuration Schema
// =============================================================================

/**
 * Billing Configuration Root
 * Complete billing.yaml structure (flat, unified configuration)
 */
export const BillingConfigSchema = z.object({
  schema_version: z.string().describe('Schema version'),
  app_identifier: z.string().describe('Application identifier'),
  enabled: z.boolean().describe('Whether billing is enabled'),
  stripe_key: z.string().min(1).describe('Stripe API key'),
  webhook_signing_secret: z.string().min(1).describe('Stripe webhook signing secret'),
  stripe_api_version: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}\.\w+$/, 'Must match format: YYYY-MM-DD.version')
    .describe('Stripe API version (e.g., 2025-11-17.clover)'),

  match_fields: z
    .array(z.string().min(1))
    .min(1)
    .default(['plan_id'])
    .describe('Fields used to build composite match key for Stripe product identification'),
  region: z
    .string()
    .nullable()
    .optional()
    .nullable()
    .describe('Region filter for this catalog instance (set via JURISDICTION env var)'),

  entitlements: z
    .record(z.string(), EntitlementDefinitionSchema)
    .describe('System-wide entitlement definitions'),

  plans: z
    .record(
      z
        .string()
        .regex(
          /^[a-z_]+(_v\d+)?$/,
          'Plan ID must be lowercase with underscores (e.g., identity, identity_plus_v1)'
        ),
      PlanDefinitionSchema
    )
    .describe('Plan definitions by plan_id (legacy plans use legacy: true flag)'),

  stripe_metadata_schema: StripeMetadataSchemaDefinition.optional().describe(
    'Stripe product metadata schema definition'
  ),
});

export type BillingConfig = z.infer<typeof BillingConfigSchema>;

// =============================================================================
// Catalog-Only Schema (no secrets/operational fields)
// =============================================================================

/**
 * Billing Catalog Schema
 * Subset of BillingConfigSchema for catalog validation without sensitive fields.
 * Generated JSON Schema: generated/schemas/billing/catalog.schema.json
 */
export const BillingCatalogSchema = z.object({
  schema_version: z.string().describe('Schema version'),
  app_identifier: z.string().describe('Application identifier'),

  match_fields: z
    .array(z.string().min(1))
    .min(1)
    .default(['plan_id'])
    .describe('Fields used to build composite match key for Stripe product identification'),
  region: z
    .string()
    .nullable()
    .optional()
    .describe('Region filter for this catalog instance'),

  entitlements: z
    .record(z.string(), EntitlementDefinitionSchema)
    .describe('System-wide entitlement definitions'),

  plans: z
    .record(
      z
        .string()
        .regex(
          /^[a-z_]+(_v\d+)?$/,
          'Plan ID must be lowercase with underscores (e.g., identity, identity_plus_v1)'
        ),
      PlanDefinitionSchema
    )
    .describe('Plan definitions by plan_id'),

  stripe_metadata_schema: StripeMetadataSchemaDefinition.optional().describe(
    'Stripe product metadata schema definition'
  ),
});

export type BillingCatalog = z.infer<typeof BillingCatalogSchema>;

// =============================================================================
// Type Aliases
// =============================================================================

export type EntitlementId = keyof BillingConfig['entitlements'];
export type PlanId = keyof BillingConfig['plans'];

// =============================================================================
// Entitlement Helpers
// =============================================================================

export function getEntitlementById(
  config: BillingConfig,
  entitlementId: string
): EntitlementDefinition | undefined {
  return config.entitlements[entitlementId];
}

export function getEntitlementsByCategory(
  config: BillingConfig,
  category: EntitlementCategory
): Array<[string, EntitlementDefinition]> {
  return Object.entries(config.entitlements).filter(([, ent]) => ent.category === category);
}

export function hasEntitlement(config: BillingConfig, entitlementId: string): boolean {
  return entitlementId in config.entitlements;
}

export function getAllEntitlementIds(config: BillingConfig): string[] {
  return Object.keys(config.entitlements);
}

// =============================================================================
// Plan Helpers
// =============================================================================

export function getPlanById(config: BillingConfig, planId: string): PlanDefinition | undefined {
  return config.plans[planId];
}

export function getAllPlanIds(config: BillingConfig): string[] {
  return Object.keys(config.plans);
}

export function getPlansSortedByDisplayOrder(
  config: BillingConfig,
  includeHidden = false
): Array<[string, PlanDefinition]> {
  return Object.entries(config.plans)
    .filter(([, plan]) => includeHidden || plan.show_on_plans_page)
    .sort(([, a], [, b]) => (b.display_order ?? 0) - (a.display_order ?? 0));
}

export function getPlansByTier(
  config: BillingConfig,
  tier: BillingTier
): Array<[string, PlanDefinition]> {
  return Object.entries(config.plans).filter(([, plan]) => plan.tier === tier);
}

export function planHasEntitlement(plan: PlanDefinition, entitlement: string): boolean {
  return plan.entitlements.includes(entitlement);
}

export function getPlanPrice(
  plan: PlanDefinition,
  interval: BillingInterval
): PlanPrice | undefined {
  return plan.prices?.find((p) => p.interval === interval);
}

export function formatLimitValue(value: LimitValue): string {
  if (value === null) return 'TBD';
  if (value === -1) return 'Unlimited';
  return value.toString();
}

export function limitValueToNumber(value: LimitValue): number {
  if (value === null) return Infinity;
  return value;
}

/**
 * Determines if a plan should be displayed with Stripe pricing on the frontend.
 *
 * Note: This is for UI filtering only. The backend catalog_push_command creates
 * ALL plans in Stripe including free tier. Free plans in Stripe are useful for:
 * - Downgrade flows (manual or after subscription cancellation)
 * - Targeted free/discounted plans for non-profits
 * - Consistent plan metadata across all tiers
 */
export function shouldCreateStripeProduct(plan: PlanDefinition): boolean {
  if (!plan.tier) return false;
  if (plan.tier === 'free') return false;
  return true;
}

/**
 * Returns plans that have Stripe pricing to display on the frontend.
 * See shouldCreateStripeProduct for filtering logic.
 */
export function getStripePlans(config: BillingConfig): Array<[string, PlanDefinition]> {
  return Object.entries(config.plans).filter(([, plan]) => shouldCreateStripeProduct(plan));
}

export function getIncompletePlans(config: BillingConfig): Array<[string, PlanDefinition]> {
  return Object.entries(config.plans).filter(([, plan]) => !plan.tier);
}

// =============================================================================
// Type Guards
// =============================================================================

export function isBillingConfig(data: unknown): data is BillingConfig {
  return BillingConfigSchema.safeParse(data).success;
}
