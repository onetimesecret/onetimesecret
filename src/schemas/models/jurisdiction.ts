import { createApiResponseSchema } from '@/schemas/api/base';
import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * @fileoverview Jurisdiction and region schemas with standardized transformations
 *
 * Key improvements:
 * 1. Uses standard model schema pattern
 * 2. Consistent transforms for type conversion
 * 3. Proper response schema handling
 * 4. Clear type boundaries
 */

// Core jurisdiction fields
const jurisdictionBaseSchema = z.object({
  display_name: z.string(),
  domain: z.string(),
  icon: z.string(),
});

// Full jurisdiction schema with base model fields
export const jurisdictionSchema = createModelSchema({
  ...jurisdictionBaseSchema.shape,
  enabled: transforms.fromString.boolean.default(true),
});

// Region schema shares same shape as jurisdiction
export const regionSchema = jurisdictionSchema;

// Config schema for region/jurisdiction settings
export const regionsConfigSchema = z.object({
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

// API response schemas
export const jurisdictionResponseSchema = createApiResponseSchema(
  jurisdictionSchema,
  jurisdictionDetailsSchema
);
export type JurisdictionResponse = z.infer<typeof jurisdictionResponseSchema>;
