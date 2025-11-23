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

export * from './billing';
export * from './billing-plans';

// Billing configuration types
export type {
  BillingConfig,
  CapabilityCategory,
  CapabilityDefinition,
  CapabilityId,
} from './billing';

export {
  BillingConfigSchema,
  getAllCapabilityIds,
  getCapabilitiesByCategory,
  getCapabilityById,
  hasCapability,
  isBillingConfig,
} from './billing';

// Plan catalog types
export type {
  BillingInterval,
  BillingTier,
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
