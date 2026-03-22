// src/schemas/contracts/config/section/jurisdiction.ts

/**
 * Jurisdiction Configuration Schema
 *
 * Defines the canonical structure for jurisdiction/region configuration.
 * Maps to the `regions:` section in config.defaults.yaml.
 *
 * This contract defines field names and output types only.
 * Wire-format transforms (string→boolean) live in shapes/config/jurisdiction.ts.
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
 */
const jurisdictionSchema = z.object({
  identifier: z.string().min(2).max(24),
  display_name: z.string(),
  domain: z.string(),
  icon: jurisdictionIconSchema,
  enabled: z.boolean().default(true),
});

/**
 * Region schema (alias for jurisdiction)
 */
const regionSchema = jurisdictionSchema;

/**
 * Canonical regions configuration schema
 */
const regionsConfigSchema = z.object({
  identifier: z.string().min(2).max(24),
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
