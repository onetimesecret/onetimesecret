// src/schemas/shapes/config/index.ts

/**
 * Config Shapes — runtime defaults and value constraints applied on top of
 * the type-only contracts. This module is what runtime consumers (CLI
 * validators, JSON Schema generation, bootstrap-derived stores) should
 * import; the contract module describes field names and types only.
 *
 * Type exports come straight from the contracts since types describe field
 * names and types — they don't depend on the defaults/bounds the shape adds.
 *
 * Selective re-exports below intentionally avoid the `export *` form so this
 * module can sit under broader aggregators (e.g., `shapes/v2/index.ts`)
 * without clashing on names like `BillingInterval` that also exist in
 * sibling shape directories (`shapes/account`).
 */

// ============================================================================
// Section Shape Schemas (the ones consumers reach for; bring in more if
// new consumers appear — keeping this list narrow protects aggregators from
// surprise re-export collisions).
// ============================================================================
export {
  capabilitiesShape,
  capabilityFlagsShape,
} from './section/capabilities';

export { developmentShape } from './section/development';

export {
  diagnosticsShape,
  diagnosticsSentryShape,
  diagnosticsSentryDefaultsShape,
  diagnosticsSentryBackendShape,
  diagnosticsSentryFrontendShape,
} from './section/diagnostics';

export {
  featuresShape,
  featuresRegionsShape,
  featuresIncomingShape,
  featuresDomainsShape,
  featuresDomainsProxyShape,
  featuresDomainsAcmeShape,
} from './section/features';

export { i18nShape } from './section/i18n';

export {
  jobsShape,
  jobsWorkersShape,
  jobsSchedulerShape,
  jobsDomainRefreshShape,
  jobsExpirationWarningsShape,
  jobsMaintenanceShape,
  workerConfigShape,
} from './section/jobs';

export {
  jurisdictionShape,
  jurisdictionIconShape,
  regionShape,
  regionsConfigShape,
  jurisdictionDetailsShape,
} from './section/jurisdiction';

export { limitsShape } from './section/limits';

export {
  emailerShape,
  mailShape,
  truemailShape,
  mailConnectionShape,
  mailValidationShape,
} from './section/mail';

export {
  secretOptionsShape,
  secretOptionBoundariesShape,
} from './section/secret_options';

export {
  siteShape,
  siteAuthenticationShape,
  siteSecretOptionsShape,
  passphraseShape,
  passwordGenerationShape,
  sessionConfigShape,
  middlewareShape,
  securityShape,
  cspShape,
} from './section/site';

export { redisDbsShape, redisShape, storageShape } from './section/storage';

export {
  userInterfaceShape,
  uiShape,
  apiShape,
  userInterfaceLogoShape,
  userInterfaceHeaderShape,
  userInterfaceFooterLinksShape,
  userInterfaceHomepageShape,
  uiCapabilitiesShape,
  uiHelpShape,
} from './section/ui';

// ============================================================================
// Top-level Shape Schemas
// ============================================================================
export {
  authConfigShape,
  authModeShape,
  simpleModeShape,
  fullModeShape,
} from './auth';

export {
  loggingConfigShape,
  logLevelShape,
  formatterShape,
  httpCaptureShape,
  loggersShape,
  httpLoggingShape,
} from './logging';

export {
  publicSecretOptionsShape,
  publicAuthenticationShape,
  publicFeaturesShape,
  publicSettingsShape,
} from './public';

export {
  staticConfigShape,
  mutableConfigShape,
  runtimeConfigShape,
  legacyStaticConfigShape,
  staticMailShape,
  mutableMailShape,
  simpleLoggingShape,
} from './config';

export {
  EntitlementDefinitionShape,
  LimitValueShape,
  PlanLimitsShape,
  PlanPriceShape,
  PlanDefinitionShape,
  MetadataFieldShape,
  StripeMetadataShapeDefinition,
  BillingConfigShape,
} from './billing';

// ============================================================================
// Jurisdiction schemas / types — re-exported from the section shape so the
// legacy `import { jurisdictionSchema } from '@/schemas/shapes/config'`
// continues to resolve. Types are sourced from the contract since field
// names/types don't depend on the shape's defaults.
// ============================================================================
export {
  jurisdictionSchema,
  jurisdictionIconSchema,
  regionSchema,
  regionsConfigSchema,
  jurisdictionDetailsSchema,
} from '@/schemas/contracts/config/section/jurisdiction';

export type {
  Jurisdiction,
  JurisdictionIcon,
  Region,
  RegionsConfig,
  JurisdictionDetails,
} from '@/schemas/contracts/config/section/jurisdiction';

// ============================================================================
// Public response schemas / types — `publicSecretOptionsShape` lives in
// `./public` and continues to be exported above. The schema names below are
// the legacy ones consumers already import from this module.
// ============================================================================
export {
  publicAuthenticationSchema,
  publicFeaturesSchema,
  publicSecretOptionsSchema,
  publicSettingsSchema,
} from '@/schemas/contracts/config/public';

export type {
  AuthenticationSettings,
  Features,
  PublicAuthenticationSettings,
  PublicFeatures,
  PublicSecretOptions,
  PublicSettings,
  SecretOptions,
} from '@/schemas/contracts/config/public';
