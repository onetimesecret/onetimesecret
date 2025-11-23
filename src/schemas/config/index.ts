// src/schemas/config/index.ts

/**
 * Configuration Schemas
 *
 * Zod schemas for application configuration files (YAML/JSON)
 *
 * Purpose:
 * - Type-safe validation of configuration files
 * - Runtime validation for config parsing
 * - TypeScript type inference for configuration usage
 * - Integration between backend YAML configs and frontend
 */

export * from './billing-plans';

export type {
  BillingInterval,
  BillingTier,
  CapabilityCategory,
  CapabilityDefinition,
  CapabilityId,
  CurrencyCode,
  LegacyPlanDefinition,
  LimitValue,
  PlanCatalog,
  PlanDefinition,
  PlanId,
  PlanLimits,
  PlanPrice,
  StripeMetadataSchemaDefinition,
  TenancyType,
  ValidationRules,
} from './billing-plans';

export {
  CATALOG_SCHEMA_VERSION,
  formatLimitValue,
  getIncompletePlans,
  getPlanById,
  getPlanPrice,
  getPlansByTier,
  getPlansSortedByDisplayOrder,
  getStripePlans,
  isPlanCatalog,
  limitValueToNumber,
  PlanCatalogSchema,
  planHasCapability,
  shouldCreateStripeProduct,
} from './billing-plans';
