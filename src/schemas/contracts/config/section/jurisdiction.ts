// src/schemas/contracts/config/section/jurisdiction.ts

/**
 * Jurisdiction Configuration Schema
 *
 * Defines the canonical structure for jurisdiction/region configuration.
 * Maps to the `regions:` section in config.defaults.yaml.
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints (e.g. identifier length bounds) belong in
 * shapes — not here. Wire-format transforms (string→boolean) live in
 * shapes/config/jurisdiction.ts.
 */

import { z } from 'zod';

/**
 * Icon configuration for jurisdiction display
 */
const jurisdictionIconSchema = z.object({
  collection: z.string(),
  name: z.string(),
});

/**
 * Canonical jurisdiction schema
 *
 * The serializer sends display_name_i18n_key (e.g., 'web.regions.jurisdictions.eu.name')
 * which components resolve via i18n. display_name is computed at runtime.
 */
const jurisdictionSchema = z.object({
  identifier: z.string(),
  display_name_i18n_key: z.string(),
  domain: z.string(),
  icon: jurisdictionIconSchema.optional(),
  enabled: z.boolean().optional(),
});

/**
 * Region schema (alias for jurisdiction)
 */
const regionSchema = jurisdictionSchema;

/**
 * Canonical regions configuration schema
 */
const regionsConfigSchema = z.object({
  identifier: z.string(),
  enabled: z.boolean(),
  current_jurisdiction: z.string(),
  jurisdictions: z.array(jurisdictionSchema),
});

/**
 * Jurisdiction details schema
 */
const jurisdictionDetailsSchema = z.object({
  is_default: z.boolean(),
  is_current: z.boolean(),
});

// Export schemas
export {
  jurisdictionSchema,
  jurisdictionIconSchema,
  regionSchema,
  regionsConfigSchema,
  jurisdictionDetailsSchema,
};

// Export types
export type Jurisdiction = z.infer<typeof jurisdictionSchema>;
export type JurisdictionIcon = z.infer<typeof jurisdictionIconSchema>;
export type Region = z.infer<typeof regionSchema>;
export type RegionsConfig = z.infer<typeof regionsConfigSchema>;
export type JurisdictionDetails = z.infer<typeof jurisdictionDetailsSchema>;
