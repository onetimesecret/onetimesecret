// src/schemas/shapes/config/billing.ts

/**
 * Billing Catalog Configuration Shape
 *
 * Adds runtime defaults and value constraints on top of the type-only
 * billing contract. The CLI (`bin/ots billing catalog validate`) consumes
 * this shape via the JSON Schema generated from the registry, so every
 * bound that previously lived on the hand-written JSON Schema (description
 * non-empty, limit-value ≥ -1, price amount ≥ 0, plan display order ≥ 0,
 * `match_fields` default `['plan_id']`) is restored here.
 *
 * @see src/schemas/contracts/config/billing.ts
 */

import { z } from 'zod';

// Re-export contract symbols (constants, type-format helpers, type exports,
// and pure-logic helpers that don't depend on bounds).
export {
  CATALOG_SCHEMA_VERSION,
  CANONICAL_PLAN_ID_PATTERN,
  CanonicalPlanIdSchema,
  EntitlementCategorySchema,
  EntitlementDefinitionSchema,
  BillingTierSchema,
  TenancyTypeSchema,
  BillingIntervalSchema,
  CurrencyCodeSchema,
  LimitValueSchema,
  PlanLimitsSchema,
  PlanPriceSchema,
  PlanDefinitionSchema,
  MetadataFieldSchema,
  StripeMetadataSchemaDefinition,
  BillingConfigSchema,
  getEntitlementById,
  getEntitlementsByCategory,
  hasEntitlement,
  getAllEntitlementIds,
  getPlanById,
  getAllPlanIds,
  getPlansSortedByDisplayOrder,
  getPlansByTier,
  planHasEntitlement,
  getPlanPrice,
  formatLimitValue,
  limitValueToNumber,
  shouldCreateStripeProduct,
  getStripePlans,
  getIncompletePlans,
  isBillingConfig,
} from '@/schemas/contracts/config/billing';

export type {
  CanonicalPlanId,
  EntitlementCategory,
  EntitlementDefinition,
  BillingTier,
  TenancyType,
  BillingInterval,
  CurrencyCode,
  LimitValue,
  PlanLimits,
  PlanPrice,
  PlanDefinition,
  StripeMetadataSchema,
  BillingConfig,
  EntitlementId,
  PlanId,
} from '@/schemas/contracts/config/billing';

import {
  CANONICAL_PLAN_ID_PATTERN,
  EntitlementCategorySchema,
  BillingTierSchema,
  TenancyTypeSchema,
  BillingIntervalSchema,
  CurrencyCodeSchema,
} from '@/schemas/contracts/config/billing';

// ============================================================================
// Entitlement Shapes
// ============================================================================

const EntitlementDefinitionShape = z.looseObject({
  category: EntitlementCategorySchema,
  description: z.string().min(1).describe('Human-readable description of the entitlement'),
});

// ============================================================================
// Plan Component Shapes
// ============================================================================

/**
 * Limit Value Shape
 *
 * Resource limits: an integer ≥ -1 (-1 = unlimited, 0+ = specific limit) or
 * null (to be determined). Restores the hand-written JSON Schema's
 * `oneOf: [{ integer, minimum: -1 }, { null }]`.
 */
const LimitValueShape = z.union([
  z.number().int().min(-1).describe('-1 = unlimited, 0+ = specific limit'),
  z.null().describe('To be determined'),
]);

const PlanLimitsShape = z.looseObject({
  organizations: LimitValueShape.describe('Maximum number of organizations'),
  members_per_team: LimitValueShape.describe('Maximum members per team'),
  custom_domains: LimitValueShape.describe('Maximum custom domains'),
  secret_lifetime: LimitValueShape.describe('Maximum secret lifetime in seconds'),
  secrets_per_day: LimitValueShape.optional().describe('Daily secret creation limit'),
});

const PlanPriceShape = z.looseObject({
  interval: BillingIntervalSchema,
  amount: z.number().int().min(0).describe('Amount in cents (e.g., 2900 = $29.00)'),
  currency: CurrencyCodeSchema.optional().describe(
    'Per-price currency override. Inherits from top-level currency when omitted.'
  ),
});

const PlanDefinitionShape = z.looseObject({
  name: z.string().min(1).describe('Display name for the plan'),
  tier: BillingTierSchema.optional().describe('Billing tier (optional for draft plans)'),
  tenancy: TenancyTypeSchema.optional().describe('Tenancy type (optional for draft plans)'),
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
    .union([z.number().int().min(0), z.null()])
    .optional()
    .describe('Sort order on plans page (higher = earlier)'),
  show_on_plans_page: z.boolean().optional().describe('Visibility on public plans page'),
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
  limits: PlanLimitsShape,
  prices: z.array(PlanPriceShape).describe('Available pricing options'),
});

const MetadataFieldShape = z.record(
  z.string(),
  z.string().describe('Field description or example value')
);

const StripeMetadataShapeDefinition = z.looseObject({
  required: z.array(MetadataFieldShape).optional().describe('Required metadata fields'),
  optional: z.array(MetadataFieldShape).optional().describe('Optional metadata fields'),
});

// ============================================================================
// Root Configuration Shape
// ============================================================================

const BillingConfigShape = z.looseObject({
  schema_version: z
    .string()
    .regex(/^\d+\.\d+$/)
    .describe('Schema version identifier'),
  app_identifier: z
    .string()
    .min(1)
    .describe('Application identifier for Stripe metadata matching'),

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
  currency: CurrencyCodeSchema.optional().describe(
    "Default currency for all products and prices. Defaults to 'cad' when not set."
  ),

  entitlements: z
    .record(z.string(), EntitlementDefinitionShape)
    .describe('System-wide entitlement definitions'),

  plans: z
    .record(
      z
        .string()
        .regex(CANONICAL_PLAN_ID_PATTERN)
        .describe('Plan ID must match canonical format: {base}_v{N} or "identity"'),
      PlanDefinitionShape
    )
    .describe('Plan definitions by plan_id (legacy plans use legacy: true flag)'),

  stripe_metadata_schema: StripeMetadataShapeDefinition.optional().describe(
    'Stripe product metadata schema definition'
  ),
});

export {
  EntitlementDefinitionShape,
  LimitValueShape,
  PlanLimitsShape,
  PlanPriceShape,
  PlanDefinitionShape,
  MetadataFieldShape,
  StripeMetadataShapeDefinition,
  BillingConfigShape,
};
