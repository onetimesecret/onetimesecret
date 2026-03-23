// src/schemas/shapes/config/index.ts
//
// Config shapes - re-exports from contracts for consistency/discoverability..
// Config data uses native JSON types (boolean, number) not wire-format transforms.

// Jurisdiction schemas and types
export {
  jurisdictionDetailsSchema,
  jurisdictionIconSchema,
  jurisdictionSchema,
  regionSchema,
  regionsConfigSchema,
  type Jurisdiction,
  type JurisdictionDetails,
  type JurisdictionIcon,
  type Region,
  type RegionsConfig,
} from '@/schemas/contracts/config/section/jurisdiction';

// Public API response schemas
export {
  publicAuthenticationSchema,
  publicFeaturesSchema,
  publicSecretOptionsSchema,
  publicSettingsSchema,
  type AuthenticationSettings,
  type Features,
  type PublicAuthenticationSettings,
  type PublicFeatures,
  type PublicSecretOptions,
  type PublicSettings,
  // Backward compatibility aliases
  type SecretOptions,
} from '@/schemas/contracts/config/public';
