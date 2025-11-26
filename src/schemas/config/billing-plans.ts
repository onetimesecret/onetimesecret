// src/schemas/config/billing-plans.ts

/**
 * Billing Plan Catalog Schema
 *
 * Zod v4 schema for etc/billing/billing-plans.yaml
 *
 * Purpose:
 * - Type-safe validation of billing plan catalog structure
 * - Runtime validation for YAML parsing
 * - TypeScript type inference for frontend usage
 * - Integration with Stripe product metadata
 *
 * Usage:
 * ```typescript
 * import { PlanCatalogSchema, type PlanCatalog } from '@/schemas/config/billing-plans';
 *
 * const catalog = PlanCatalogSchema.parse(yamlData);
 * const plan = catalog.plans.identity_plus_v1;
 * ```
 */

import { z } from 'zod/v4';

/**
 * Schema Version
 * Must match schema_version in YAML file
 */
export const CATALOG_SCHEMA_VERSION = '1.0';

/**
 * NOTE: Capability definitions have moved to billing.ts (billing.yaml)
 * Plans reference capabilities by ID string.
 * Import capability schemas from './billing' if needed.
 */

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
export const CurrencyCodeSchema = z.enum(['usd', 'eur', 'cad']);

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
  teams: LimitValueSchema.describe('Maximum number of teams'),
  members_per_team: LimitValueSchema.describe('Maximum members per team'),
  custom_domains: LimitValueSchema.describe('Maximum custom domains'),
  secret_lifetime: LimitValueSchema.describe('Maximum secret lifetime in seconds'),
  secrets_per_day: LimitValueSchema.describe('Daily secret creation limit'),
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
  region: z.string().min(1).optional().describe('Geographic region (EU, CA, global)'),
  display_order: z
    .number()
    .int()
    .nonnegative()
    .describe('Sort order on plans page (higher = earlier)'),
  show_on_plans_page: z.boolean().describe('Visibility on public plans page'),
  description: z.string().min(1).optional().describe('Plan description for documentation'),

  capabilities: z.array(z.string().min(1)).describe('Array of capability IDs'),
  limits: PlanLimitsSchema,
  prices: z.array(PlanPriceSchema).describe('Available pricing options'),
});

export type PlanDefinition = z.infer<typeof PlanDefinitionSchema>;

/**
 * Legacy Plan Definition
 * Grandfathered plans no longer offered to new customers
 */
export const LegacyPlanDefinitionSchema = PlanDefinitionSchema.extend({
  grandfathered_until: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe('ISO date until which plan is grandfathered (YYYY-MM-DD)'),
});

export type LegacyPlanDefinition = z.infer<typeof LegacyPlanDefinitionSchema>;

/**
 * Stripe Metadata Field Definition
 * Schema for required/optional Stripe product metadata fields
 */
export const MetadataFieldSchema = z.record(
  z.string(),
  z.string().describe('Field description or example value')
);

/**
 * Stripe Metadata Schema Definition
 * Defines validation rules for Stripe product metadata
 */
export const StripeMetadataSchemaDefinition = z.object({
  required: MetadataFieldSchema.describe('Required metadata fields'),
  optional: MetadataFieldSchema.optional().describe('Optional metadata fields'),
});

export type StripeMetadataSchemaDefinition = z.infer<typeof StripeMetadataSchemaDefinition>;

/**
 * Validation Rules
 * Regex patterns and allowed values for catalog validation
 */
export const ValidationRulesSchema = z.object({
  plan_id_format: z.string().describe('Regex pattern for plan_id format'),
  tier_values: z.array(BillingTierSchema),
  tenancy_values: z.array(TenancyTypeSchema),
  limit_values: z.string().describe('Description of valid limit value ranges'),
  price_intervals: z.array(BillingIntervalSchema),
  price_currencies: z.array(CurrencyCodeSchema),
});

export type ValidationRules = z.infer<typeof ValidationRulesSchema>;

/**
 * Plan Catalog Root Schema
 * Complete billing plan catalog structure
 *
 * NOTE: Configuration (capabilities, stripe_api_version) moved to billing.yaml
 * Plans reference capabilities by ID string.
 */
export const PlanCatalogSchema = z.object({
  schema_version: z.literal(CATALOG_SCHEMA_VERSION).describe('Catalog schema version'),

  plans: z
    .record(
      z.string().regex(/^[a-z_]+_v\d+$/, 'Plan ID must match format: name_v1'),
      PlanDefinitionSchema
    )
    .describe('Active plan definitions by plan_id'),

  legacy_plans: z
    .record(z.string(), LegacyPlanDefinitionSchema)
    .optional()
    .describe('Grandfathered plan definitions'),

  stripe_metadata_schema: StripeMetadataSchemaDefinition.optional().describe(
    'Stripe product metadata schema definition'
  ),

  validation: ValidationRulesSchema.optional().describe('Validation rules for catalog structure'),
});

export type PlanCatalog = z.infer<typeof PlanCatalogSchema>;

/**
 * Plan ID Type
 * Type-safe plan identifiers from catalog
 */
export type PlanId = keyof PlanCatalog['plans'];

/**
 * Capability ID Type
 * NOTE: Moved to billing.ts - import from './billing' if needed
 */

/**
 * Helper: Extract plan by ID with type safety
 *
 * @param catalog - Validated plan catalog
 * @param planId - Plan identifier
 * @returns Plan definition or undefined
 */
export function getPlanById(catalog: PlanCatalog, planId: string): PlanDefinition | undefined {
  return catalog.plans[planId];
}

/**
 * Helper: Get all plans sorted by display order
 *
 * @param catalog - Validated plan catalog
 * @param includeHidden - Include plans not shown on plans page
 * @returns Array of [planId, plan] tuples sorted by display_order
 */
export function getPlansSortedByDisplayOrder(
  catalog: PlanCatalog,
  includeHidden = false
): Array<[string, PlanDefinition]> {
  return Object.entries(catalog.plans)
    .filter(([, plan]) => includeHidden || plan.show_on_plans_page)
    .sort(([, a], [, b]) => b.display_order - a.display_order);
}

/**
 * Helper: Get plans by tier
 *
 * @param catalog - Validated plan catalog
 * @param tier - Billing tier to filter by
 * @returns Array of plan definitions matching tier
 */
export function getPlansByTier(
  catalog: PlanCatalog,
  tier: BillingTier
): Array<[string, PlanDefinition]> {
  return Object.entries(catalog.plans).filter(([, plan]) => plan.tier === tier);
}

/**
 * Helper: Check if plan has capability
 *
 * @param plan - Plan definition
 * @param capability - Capability ID to check
 * @returns True if plan includes capability
 */
export function planHasCapability(plan: PlanDefinition, capability: string): boolean {
  return plan.capabilities.includes(capability);
}

/**
 * Helper: Get price for plan and interval
 *
 * @param plan - Plan definition
 * @param interval - Billing interval
 * @returns Price definition or undefined
 */
export function getPlanPrice(
  plan: PlanDefinition,
  interval: BillingInterval
): PlanPrice | undefined {
  return plan.prices.find((p) => p.interval === interval);
}

/**
 * Helper: Format limit value for display
 *
 * @param value - Limit value from plan
 * @returns Human-readable limit string
 */
export function formatLimitValue(value: LimitValue): string {
  if (value === null) return 'TBD';
  if (value === -1) return 'Unlimited';
  return value.toString();
}

/**
 * Helper: Convert limit value to number (for comparisons)
 *
 * @param value - Limit value from plan
 * @returns Number representation (-1 for unlimited, Infinity for null/TBD, actual value otherwise)
 */
export function limitValueToNumber(value: LimitValue): number {
  if (value === null) return Infinity; // TBD treated as unlimited for now
  return value;
}

/**
 * Helper: Check if plan should be created in Stripe
 *
 * Plans are skipped if:
 * - tier is 'free' (no Stripe product needed)
 * - tier is undefined/null (incomplete definition)
 *
 * @param plan - Plan definition
 * @returns True if plan should be created in Stripe
 */
export function shouldCreateStripeProduct(plan: PlanDefinition): boolean {
  // Skip if no tier defined (incomplete/draft plan)
  if (!plan.tier) return false;

  // Skip free tier (no Stripe product)
  if (plan.tier === 'free') return false;

  return true;
}

/**
 * Helper: Get plans that should be created in Stripe
 *
 * Filters out free tier and incomplete plans
 *
 * @param catalog - Validated plan catalog
 * @returns Array of [planId, plan] tuples for Stripe creation
 */
export function getStripePlans(catalog: PlanCatalog): Array<[string, PlanDefinition]> {
  return Object.entries(catalog.plans).filter(([, plan]) => shouldCreateStripeProduct(plan));
}

/**
 * Helper: Get incomplete plans (missing tier)
 *
 * @param catalog - Validated plan catalog
 * @returns Array of [planId, plan] tuples for incomplete plans
 */
export function getIncompletePlans(catalog: PlanCatalog): Array<[string, PlanDefinition]> {
  return Object.entries(catalog.plans).filter(([, plan]) => !plan.tier);
}

/**
 * Type guard: Check if catalog is valid
 *
 * @param data - Unknown data to validate
 * @returns True if data matches PlanCatalog schema
 */
export function isPlanCatalog(data: unknown): data is PlanCatalog {
  return PlanCatalogSchema.safeParse(data).success;
}
