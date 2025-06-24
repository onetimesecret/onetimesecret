import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

/**
 * @fileoverview Jurisdiction and region schemas with standardized transformations
 *
 * We use these schemas for the settings defined in etc/config.yaml.
 */

// Jurisdiction schema
export const jurisdictionSchema = z.object({
  identifier: z.string().min(2).max(24),
  display_name: z.string(),
  domain: z.string(),
  icon: z.object({
    collection: z.string(),
    name: z.string(),
  }),
  enabled: transforms.fromString.boolean.default(true),
});

// Region schema shares same shape as jurisdiction
export const regionSchema = jurisdictionSchema;

// Config schema for region/jurisdiction settings
export const regionsConfigSchema = z.object({
  identifier: z.string().min(2).max(24),
  enabled: transforms.fromString.boolean,
  current_jurisdiction: z.string(),
  jurisdictions: z.array(jurisdictionSchema),
});

// Details schema for jurisdiction-specific metadata
export const jurisdictionDetailsSchema = z.object({
  is_default: transforms.fromString.boolean,
  is_current: transforms.fromString.boolean,
});

// Export types
export type Jurisdiction = z.infer<typeof jurisdictionSchema>;
export type Region = z.infer<typeof regionSchema>;
export type RegionsConfig = z.infer<typeof regionsConfigSchema>;
export type JurisdictionDetails = z.infer<typeof jurisdictionDetailsSchema>;
