// src/schemas/contracts/config/billing.ts

/**
 * Billing Catalog Configuration Schema
 *
 * Zod v4 schema for the billing catalog defined in etc/billing.yaml
 * (unified flat-structure configuration).
 *
 * Per contracts convention, this schema describes field names and types
 * only. Value constraints (description min length, limit value `>= -1`,
 * price amount `>= 0`, plan display_order `>= 0`, match_fields default
 * `['plan_id']`) live in `shapes/config/billing.ts`, which is what the
 * JSON Schema generator feeds to `bin/ots billing catalog validate`.
 *
 * Structural / type-format helpers stay here:
 *
 * - `z.looseObject` mirrors the hand-written JSON Schema's lack of
 *   `additionalProperties: false`. The CLI validates the entire billing
 *   YAML, which carries runtime keys not part of the catalog (`enabled`,
 *   `stripe_key`, `webhook_signing_secret`, `stripe_api_version`) plus
 *   extra nested keys (`limits.teams`, `prices[].price_id`,
 *   `prices[].metadata`). Loose objects allow these through.
 * - `.regex()` and `.enum()` stay — they describe valid value formats.
 * - Required vs optional fields mirror the hand-written `required` arrays.
 *
 * Purpose:
 * - Type-safe field definitions for the billing catalog
 * - TypeScript type inference for billing config usage
 *
 * Usage:
 * ```typescript
 * import { BillingConfigSchema, type BillingConfig } from '@/schemas/contracts/config/billing';
 *
 * const config = BillingConfigSchema.parse(yamlData);
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

/**
 * Canonical Plan ID Pattern
 *
 * Enforces the naming convention for plan IDs.
 *
 * Valid: free_v1, identity_plus_v1, team_plus_v1, legacy_plan_v1, identity
 *
 * @see https://github.com/onetimesecret/onetimesecret/issues/3135 Section 9
 */
export const CANONICAL_PLAN_ID_PATTERN =
  /^(free|identity_plus|team_plus|legacy_plan)_v\d+$|^identity$/;

/**
 * Canonical Plan ID Schema
 *
 * Reusable schema for validating plan IDs at API boundaries.
 * Use this for fields like `planid`, `target_plan_id`, etc.
 */
export const CanonicalPlanIdSchema = z
  .string()
  .regex(CANONICAL_PLAN_ID_PATTERN)
  .describe('Plan ID in canonical format: {base}_v{N} or "identity"');

export type CanonicalPlanId = z.infer<typeof CanonicalPlanIdSchema>;

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
export const EntitlementDefinitionSchema = z.looseObject({
  category: EntitlementCategorySchema,
  description: z.string().describe('Human-readable description of the entitlement'),
});

export type EntitlementDefinition = z.infer<typeof EntitlementDefinitionSchema>;

// =============================================================================
// Plan Component Schemas
// =============================================================================

/**
 * Billing Tier
 *
 * Hierarchical plan tiers. This is the authoritative tier enum; the
 * runtime `planTypeSchema` in src/schemas/contracts/billing.ts reuses it.
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
export const CurrencyCodeSchema = z.enum(['cad', 'eur', 'gbp', 'nzd', 'usd']);

export type CurrencyCode = z.infer<typeof CurrencyCodeSchema>;

/**
 * Limit Value
 *
 * Resource limits expressed as a number (where -1 carries the "unlimited"
 * convention) or null (to be determined). The lower bound (`>= -1`) is a
 * value constraint and lives in the shape.
 */
export const LimitValueSchema = z.union([
  z.number().describe('-1 = unlimited, 0+ = specific limit'),
  z.null().describe('To be determined'),
]);

export type LimitValue = z.infer<typeof LimitValueSchema>;

/**
 * Plan Limits
 * Resource constraints for a billing plan
 */
export const PlanLimitsSchema = z.looseObject({
  organizations: LimitValueSchema.describe('Maximum number of organizations'),
  total_members_per_org: LimitValueSchema.describe('Maximum members per org'),
  custom_domains: LimitValueSchema.describe('Maximum custom domains'),
  secret_lifetime: LimitValueSchema.describe('Maximum secret lifetime in seconds'),
  secrets_per_day: LimitValueSchema.optional().describe('Daily secret creation limit'),
});

export type PlanLimits = z.infer<typeof PlanLimitsSchema>;

/**
 * Plan Price
 * Stripe price configuration for a billing interval
 */
export const PlanPriceSchema = z.looseObject({
  interval: BillingIntervalSchema,
  amount: z.number().describe('Amount in cents (e.g., 2900 = $29.00)'),
  currency: CurrencyCodeSchema.optional().describe(
    'Per-price currency override. Inherits from top-level currency when omitted.'
  ),
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
export const PlanDefinitionSchema = z.looseObject({
  name: z.string().describe('Display name for the plan'),
  tier: BillingTierSchema.optional().describe('Billing tier (optional for draft plans)'),
  tenancy: TenancyTypeSchema.optional().describe('Tenancy type (optional for draft plans)'),
  // Region resolves from an ERB-templated env var in real configs and may
  // be empty (YAML null); allow null/absent in addition to a string.
  region: z
    .string()
    .nullable()
    .optional()
    .describe("Region identifier for composite matching (e.g., 'EU', 'US')"),
  stripe_product_id: z
    .string()
    .regex(/^prod_/)
    .optional()
    .describe('Direct Stripe product ID binding (escape hatch for matching issues)'),
  plan_name_label: z.string().optional().describe('i18n key for plan category label'),
  display_order: z
    .union([z.number(), z.null()])
    .optional()
    .describe('Sort order on plans page (higher = earlier)'),
  show_on_plans_page: z.boolean().optional().describe('Visibility on public plans page'),
  includes_plan: z
    .string()
    .optional()
    .describe('Plan ID this plan includes (for "Includes everything in X" display)'),
  description: z.string().optional().describe('Plan description for documentation'),
  legacy: z.boolean().optional().describe('Marks plan as legacy/grandfathered (no longer offered)'),
  grandfathered_until: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe('ISO date until which plan is grandfathered (YYYY-MM-DD)'),

  entitlements: z.array(z.string()).describe('Array of entitlement IDs'),
  features: z.array(z.string()).optional().describe('Array of i18n feature keys for UI display'),
  limits: PlanLimitsSchema,
  prices: z.array(PlanPriceSchema).describe('Available pricing options'),
});

export type PlanDefinition = z.infer<typeof PlanDefinitionSchema>;

/**
 * Stripe Metadata Field map
 *
 * A free-form map of metadata field name -> description/example value.
 */
export const MetadataFieldSchema = z.record(
  z.string(),
  z.string().describe('Field description or example value')
);

/**
 * Stripe Metadata Schema Definition
 *
 * Informational description of Stripe product metadata conventions.
 * `required`/`optional` are arrays of single-entry field maps, matching
 * the hand-written schema. Both keys are optional.
 */
export const StripeMetadataSchemaDefinition = z.looseObject({
  required: z.array(MetadataFieldSchema).optional().describe('Required metadata fields'),
  optional: z.array(MetadataFieldSchema).optional().describe('Optional metadata fields'),
});

export type StripeMetadataSchema = z.infer<typeof StripeMetadataSchemaDefinition>;

// =============================================================================
// Root Configuration Schema
// =============================================================================

/**
 * Billing Configuration Root
 *
 * The catalog portion of billing.yaml. Modelled as a loose object so the
 * runtime/secret keys present in the YAML file (`enabled`, `stripe_key`,
 * `webhook_signing_secret`, `stripe_api_version`) pass validation exactly
 * as they did under the hand-written JSON Schema.
 */
export const BillingConfigSchema = z.looseObject({
  schema_version: z
    .string()
    .regex(/^\d+\.\d+$/)
    .describe('Schema version identifier'),
  app_identifier: z.string().describe('Application identifier for Stripe metadata matching'),

  match_fields: z
    .array(z.string())
    .optional()
    .describe('Fields used to build composite match key for Stripe product identification'),
  // Region resolves from an ERB-templated env var and may be empty (null).
  region: z.string().nullable().optional().describe('Region filter for this catalog instance'),
  currency: CurrencyCodeSchema.optional().describe(
    "Default currency for all products and prices. Defaults to 'cad' when not set."
  ),

  entitlements: z
    .record(z.string(), EntitlementDefinitionSchema)
    .describe('System-wide entitlement definitions'),

  plans: z
    .record(
      z
        .string()
        .regex(CANONICAL_PLAN_ID_PATTERN)
        .describe('Plan ID must match canonical format: {base}_v{N} or "identity"'),
      PlanDefinitionSchema
    )
    .describe('Plan definitions by plan_id (legacy plans use legacy: true flag)'),

  stripe_metadata_schema: StripeMetadataSchemaDefinition.optional().describe(
    'Stripe product metadata schema definition'
  ),
});

export type BillingConfig = z.infer<typeof BillingConfigSchema>;

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
  return plan.prices.find((p) => p.interval === interval);
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
