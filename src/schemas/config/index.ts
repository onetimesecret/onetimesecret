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

export * from './billing-catalog';

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
} from './billing-catalog';

export {
  CATALOG_SCHEMA_VERSION,
  formatLimitValue,
  getPlanById,
  getPlanPrice,
  getPlansByTier,
  getPlansSortedByDisplayOrder,
  isPlanCatalog,
  limitValueToNumber,
  PlanCatalogSchema,
  planHasCapability,
} from './billing-catalog';
