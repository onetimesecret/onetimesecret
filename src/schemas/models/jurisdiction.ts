// src/schemas/jurisdiction/index.ts
import { z } from 'zod';


// BaseEntity schema with common properties
export const baseEntitySchema = z.object({
  identifier: z.string(),
  display_name: z.string(),
  domain: z.string(),
  icon: z.string(),
});

/**
 * Inferred TypeScript type for BaseEntity
 */
export type BaseEntity = z.infer<typeof baseEntitySchema>;


/**
 * Jurisdiction schema extending BaseEntity
 */
export const jurisdictionSchema = baseEntitySchema.extend({});

/**
 * Inferred TypeScript type for Jurisdiction
 */
export type Jurisdiction = z.infer<typeof jurisdictionSchema>;

/**
 * Region schema extending BaseEntity
 */
export const regionSchema = baseEntitySchema.extend({});

/**
 * Inferred TypeScript type for Region
 */
export type Region = z.infer<typeof regionSchema>;

/**
 * RegionsConfig schema
 */
export const regionsConfigSchema = z.object({
  enabled: z.boolean(),
  current_jurisdiction: z.string(),
  jurisdictions: z.array(jurisdictionSchema),
});

/**
 * Inferred TypeScript type for RegionsConfig
 */
export type RegionsConfig = z.infer<typeof regionsConfigSchema>;
