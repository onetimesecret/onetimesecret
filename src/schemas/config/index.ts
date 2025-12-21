// src/schemas/config/index.ts

/**
 * Configuration Schemas
 *
 * Zod v4 schemas for application configuration files (YAML/JSON)
 *
 * Purpose:
 * - Type-safe validation of configuration files
 * - Runtime validation for config parsing
 * - TypeScript type inference for configuration usage
 * - Integration between backend YAML configs and frontend
 *
 * Structure:
 * - shared/: Common primitives and user type definitions
 * - section/: Individual configuration section schemas
 * - config.ts: Main config schemas (static, mutable, runtime, API response)
 * - auth.ts: Authentication configuration (auth.defaults.yaml)
 * - logging.ts: Logging configuration (logging.defaults.yaml)
 * - billing.ts: Billing configuration (billing.yaml)
 * - billing-plans.ts: Plan catalog configuration (billing-catalog.yaml)
 */

// ============================================================================
// Shared Primitives
// ============================================================================
export { nullableString, ValidKeys } from './shared';

// ============================================================================
// Section Schemas
// ============================================================================
export * from './section';

// ============================================================================
// Main Configuration (config.defaults.yaml)
// ============================================================================
export {
  // Type helpers
  booleanOrString,
  numberOrString,
  // API response schemas (flexible)
  apiInterfaceSchema,
  apiSecretOptionsSchema,
  apiEmailerSchema,
  apiMailSchema,
  apiDiagnosticsSchema,
  apiAuthenticationSchema,
  apiLoggingSchema,
  apiBillingSchema,
  apiFeaturesSchema,
  systemSettingsSchema,
  systemSettingsDetailsSchema,
  // Config file schemas (strict)
  staticConfigSchema,
  mutableConfigSchema,
  runtimeConfigSchema,
  legacyStaticConfigSchema,
  // Section re-exports
  siteSchema,
  siteAuthenticationSchema,
  passphraseSchema,
  passwordGenerationSchema,
  storageSchema,
  redisSchema,
  emailerSchema,
  mailSchema,
  mailConnectionSchema,
  mailValidationSchema,
  diagnosticsSchema,
  featuresSchema,
  capabilitiesSchema,
  i18nSchema,
  developmentSchema,
  experimentalSchema,
  userInterfaceSchema,
  apiSchema,
  limitsSchema,
  secretOptionsSchema,
  loggingSchema,
} from './config';

export type {
  StaticConfig,
  MutableConfig,
  RuntimeConfig,
  LegacyStaticConfig,
  SystemSettings,
  SystemSettingsDetails,
} from './config';

// Backward compatibility aliases
export type MutableConfigDetails = import('./config').MutableConfig;

// ============================================================================
// Authentication Configuration (auth.defaults.yaml)
// ============================================================================
export {
  authConfigSchema,
  authModeSchema,
  simpleModeSchema,
  fullModeSchema,
  isAuthConfig,
} from './auth';

export type { AuthConfig, AuthMode, SimpleModeConfig, FullModeConfig } from './auth';

// NOTE: sessionConfigSchema has been moved to site config (section/site.ts)
// Re-export from there for backwards compatibility
export { sessionConfigSchema } from './section/site';
export type { SessionConfig } from './section/site';

// ============================================================================
// Logging Configuration (logging.defaults.yaml)
// ============================================================================
export {
  loggingConfigSchema,
  logLevelSchema,
  formatterSchema,
  httpCaptureSchema,
  loggersSchema,
  httpLoggingSchema,
  isLoggingConfig,
} from './logging';

export type {
  LoggingConfig,
  LogLevel,
  Formatter,
  HttpCapture,
  Loggers,
  HttpLogging,
} from './logging';

// ============================================================================
// Billing Configuration (billing.yaml)
// ============================================================================
export {
  BillingConfigSchema,
  EntitlementCategorySchema,
  EntitlementDefinitionSchema,
  getAllEntitlementIds,
  getEntitlementsByCategory,
  getEntitlementById,
  hasEntitlement,
  isBillingConfig,
} from './billing';

export type {
  BillingConfig,
  EntitlementCategory,
  EntitlementDefinition,
  EntitlementId,
} from './billing';

// ============================================================================
// Plan Catalog Configuration (billing-catalog.yaml)
// ============================================================================
export {
  CATALOG_SCHEMA_VERSION,
  BillingTierSchema,
  TenancyTypeSchema,
  BillingIntervalSchema,
  CurrencyCodeSchema,
  LimitValueSchema,
  PlanLimitsSchema,
  PlanPriceSchema,
  PlanDefinitionSchema,
  LegacyPlanDefinitionSchema,
  MetadataFieldSchema,
  StripeMetadataSchemaDefinition,
  ValidationRulesSchema,
  PlanCatalogSchema,
  formatLimitValue,
  getIncompletePlans,
  getPlanById,
  getPlanPrice,
  getPlansByTier,
  getPlansSortedByDisplayOrder,
  getStripePlans,
  isPlanCatalog,
  limitValueToNumber,
  planHasEntitlement,
  shouldCreateStripeProduct,
} from './billing-plans';

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
  StripeMetadataSchemaDefinition as StripeMetadataSchema,
  TenancyType,
  ValidationRules,
} from './billing-plans';
