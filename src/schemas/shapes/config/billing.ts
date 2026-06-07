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
 * `augment` handles the looseObject schemas. `LimitValue` is a `z.union`
 * and the catalog's `entitlements` / `plans` are `z.record`s, neither of
 * which augment recurses into — those are reconstructed manually in the
 * affected fields' leaf transforms.
 *
 * @see src/schemas/contracts/config/billing.ts
 */

import {
  BillingConfigSchema,
  BillingIntervalSchema,
  BillingTierSchema,
  CANONICAL_PLAN_ID_PATTERN,
  CanonicalPlanIdSchema,
  CATALOG_SCHEMA_VERSION,
  CurrencyCodeSchema,
  EntitlementCategorySchema,
  EntitlementDefinitionSchema,
  formatLimitValue,
  getAllEntitlementIds,
  getAllPlanIds,
  getEntitlementById,
  getEntitlementsByCategory,
  getIncompletePlans,
  getPlanById,
  getPlanPrice,
  getPlansByTier,
  getPlansSortedByDisplayOrder,
  getStripePlans,
  hasEntitlement,
  isBillingConfig,
  LimitValueSchema,
  limitValueToNumber,
  MetadataFieldSchema,
  PlanDefinitionSchema,
  planHasEntitlement,
  PlanLimitsSchema,
  PlanPriceSchema,
  shouldCreateStripeProduct,
  StripeMetadataSchemaDefinition,
  TenancyTypeSchema,
} from '@/schemas/contracts/config/billing';
import { augment } from '@/schemas/utils/augment';
import { z } from 'zod';

export {
  BillingConfigSchema,
  BillingIntervalSchema,
  BillingTierSchema,
  CANONICAL_PLAN_ID_PATTERN,
  CanonicalPlanIdSchema,
  CATALOG_SCHEMA_VERSION,
  CurrencyCodeSchema,
  EntitlementCategorySchema,
  EntitlementDefinitionSchema,
  formatLimitValue,
  getAllEntitlementIds,
  getAllPlanIds,
  getEntitlementById,
  getEntitlementsByCategory,
  getIncompletePlans,
  getPlanById,
  getPlanPrice,
  getPlansByTier,
  getPlansSortedByDisplayOrder,
  getStripePlans,
  hasEntitlement,
  isBillingConfig,
  LimitValueSchema,
  limitValueToNumber,
  MetadataFieldSchema,
  PlanDefinitionSchema,
  planHasEntitlement,
  PlanLimitsSchema,
  PlanPriceSchema,
  shouldCreateStripeProduct,
  StripeMetadataSchemaDefinition,
  TenancyTypeSchema,
};

export type {
  BillingConfig,
  BillingInterval,
  BillingTier,
  CanonicalPlanId,
  CurrencyCode,
  EntitlementCategory,
  EntitlementDefinition,
  EntitlementId,
  LimitValue,
  PlanDefinition,
  PlanId,
  PlanLimits,
  PlanPrice,
  StripeMetadataSchema,
  TenancyType,
} from '@/schemas/contracts/config/billing';

// =============================================================================
// Entitlement Shapes
// =============================================================================

const EntitlementDefinitionShape = augment(EntitlementDefinitionSchema, {
  description: (s) => s.min(1).describe('Human-readable description of the entitlement'),
});

// =============================================================================
// Plan Component Shapes
// =============================================================================

/**
 * Limit Value Shape
 *
 * Resource limits: an integer ≥ -1 (-1 = unlimited, 0+ = specific limit) or
 * null (to be determined). Restores the hand-written JSON Schema's
 * `oneOf: [{ integer, minimum: -1 }, { null }]`.
 *
 * Not built via augment because the contract's `z.union(...)` isn't a
 * `ZodObject`. Reconstructed manually with the bounds restored.
 */
const LimitValueShape = z.union([
  z.number().int().min(-1).describe('-1 = unlimited, 0+ = specific limit'),
  z.null().describe('To be determined'),
]);

const PlanLimitsShape = augment(PlanLimitsSchema, {
  organizations: () => LimitValueShape.describe('Maximum number of organizations'),
  total_members_per_org: () => LimitValueShape.describe('Maximum members per organization'),
  custom_domains: () => LimitValueShape.describe('Maximum custom domains'),
  secret_lifetime: () => LimitValueShape.describe('Maximum secret lifetime in seconds'),
  secrets_per_day: () => LimitValueShape.optional().describe('Daily secret creation limit'),
});

const PlanPriceShape = augment(PlanPriceSchema, {
  amount: (n) => n.int().min(0).describe('Amount in cents (e.g., 2900 = $29.00)'),
});

const PlanDefinitionShape = augment(PlanDefinitionSchema, {
  name: (s) => s.min(1).describe('Display name for the plan'),
  display_order: () =>
    z
      .union([z.number().int().min(0), z.null()])
      .optional()
      .describe('Sort order on plans page (higher = earlier)'),
  description: (s) => s.min(1).optional().describe('Plan description for documentation'),
  entitlements: () => z.array(z.string().min(1)).describe('Array of entitlement IDs'),
  features: () =>
    z.array(z.string().min(1)).optional().describe('Array of i18n feature keys for UI display'),
  limits: () => PlanLimitsShape,
  prices: () => z.array(PlanPriceShape).describe('Available pricing options'),
});

const MetadataFieldShape = MetadataFieldSchema;

const StripeMetadataShapeDefinition = StripeMetadataSchemaDefinition;

// =============================================================================
// Root Configuration Shape
// =============================================================================

const BillingConfigShape = augment(BillingConfigSchema, {
  app_identifier: (s) => s.min(1).describe('Application identifier for Stripe metadata matching'),
  // The contract's array element is z.string() with no inner bound — augment's
  // leaf can chain on the array but can't replace the element type. Reconstruct
  // from scratch to re-add the `.min(1)` per-string constraint alongside the
  // array-level `.min(1)` and default.
  match_fields: () =>
    z
      .array(z.string().min(1))
      .min(1)
      .default(['plan_id'])
      .describe('Fields used to build composite match key for Stripe product identification'),
  entitlements: () =>
    z
      .record(z.string(), EntitlementDefinitionShape)
      .describe('System-wide entitlement definitions'),
  plans: () =>
    z
      .record(
        z
          .string()
          .regex(CANONICAL_PLAN_ID_PATTERN)
          .describe('Plan ID must match canonical format: {base}_v{N} or "identity"'),
        PlanDefinitionShape
      )
      .describe('Plan definitions by plan_id (legacy plans use legacy: true flag)'),
});

export {
  BillingConfigShape,
  EntitlementDefinitionShape,
  LimitValueShape,
  MetadataFieldShape,
  PlanDefinitionShape,
  PlanLimitsShape,
  PlanPriceShape,
  StripeMetadataShapeDefinition,
};
