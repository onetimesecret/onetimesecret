// src/schemas/contracts/config/index.ts

/**
 * Configuration Schemas
 *
 * Zod v4 schemas for application configuration files (YAML/JSON)
 *
 * Purpose:
 * - Type-safe field definitions for configuration files
 * - TypeScript type inference for configuration usage
 * - Integration between backend YAML configs and frontend
 *
 * Structure:
 * - shared/: Common primitives and user type definitions
 * - section/: Individual configuration section schemas
 * - config.ts: Main config schemas (static, mutable, runtime, API response)
 * - auth.ts: Authentication configuration (auth.defaults.yaml)
 * - logging.ts: Logging configuration (logging.defaults.yaml)
 * - billing.ts: Unified billing configuration (billing.yaml)
 *
 * ## Tradeoff: contracts are type-only (#3212)
 *
 * Following the entity-contract convention, every config contract in this
 * directory describes field names and output types only — no defaults, no
 * numeric/length bounds. Structural modifiers (`.optional`, `.nullable`,
 * `.nullish`) and type-format helpers (`.regex`, `.email`, `.enum`,
 * `.literal`, `.union`, `z.looseObject`) are retained because they describe
 * the type itself.
 *
 * Consequences:
 * - **Defaults**: now the runtime layer's responsibility (Ruby application
 *   config loader / frontend store). The contracts no longer fill in missing
 *   fields when parsing partial input.
 * - **CLI validators**: `bin/ots config validate` and
 *   `bin/ots billing catalog validate` continue to validate structure and
 *   types, but no longer enforce removed value bounds (e.g. port ranges,
 *   passphrase length bounds, plan limit `>= -1`, Redis db number range,
 *   empty-string rejection). The CLIs are intentionally less strict during
 *   this interim.
 * - **Shapes layer**: removed defaults/bounds that have a consumer (e.g.
 *   frontend code that expected a numeric default) will move to
 *   `src/schemas/shapes/config/` when that layer is introduced — a separate
 *   design decision.
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
  userInterfaceSchema,
  apiSchema,
  limitsSchema,
  secretOptionsSchema,
  jobsSchema,
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
// Billing Configuration (billing.yaml - unified flat structure)
// ============================================================================
export {
  // Constants
  CATALOG_SCHEMA_VERSION,
  // Root schema
  BillingConfigSchema,
  // Entitlement schemas
  EntitlementCategorySchema,
  EntitlementDefinitionSchema,
  // Plan component schemas
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
  // Entitlement helpers
  getEntitlementById,
  getEntitlementsByCategory,
  hasEntitlement,
  getAllEntitlementIds,
  // Plan helpers
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
  // Type guard
  isBillingConfig,
} from './billing';

export type {
  BillingConfig,
  EntitlementCategory,
  EntitlementDefinition,
  EntitlementId,
  BillingTier,
  TenancyType,
  BillingInterval,
  CurrencyCode,
  LimitValue,
  PlanLimits,
  PlanPrice,
  PlanDefinition,
  StripeMetadataSchema,
  PlanId,
} from './billing';

// ============================================================================
// Public API Response Schemas (config data serialized to JSON)
// ============================================================================
export {
  publicSecretOptionsSchema,
  publicAuthenticationSchema,
  publicFeaturesSchema,
  publicSettingsSchema,
} from './public';

export type {
  PublicSecretOptions,
  PublicAuthenticationSettings,
  PublicSettings,
  PublicFeatures,
  // Backward compatibility aliases
  SecretOptions,
  AuthenticationSettings,
  Features,
} from './public';
