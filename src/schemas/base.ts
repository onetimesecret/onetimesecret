import { dateFromSeconds } from '@/utils/transforms';
import { z } from 'zod';

/**
 * Core schema definitions used across all models
 * Provides base transformation and validation rules
 */

// Base API Response
export const baseApiResponseSchema = z.object({
  success: z.boolean(),
  record: z.object({
    // Use dateFromSeconds transform directly in the schema
    created: z.union([z.string(), z.number()]).transform((val) => dateFromSeconds.parse(val)),
    updated: z.union([z.string(), z.number()]).transform((val) => dateFromSeconds.parse(val)),
    // Other fields as needed
  }),
});

export const emptyApiRecordSchema = z.object({});

export const baseApiRecordSchema = z.object({
  identifier: z.string(),
  created: z.union([z.string(), z.number()]).transform((val) => new Date(Number(val) * 1000)),
  updated: z.union([z.string(), z.number()]).transform((val) => new Date(Number(val) * 1000)),
});

// Transformed Base Record
export const transformedBaseRecordSchema = z.object({
  identifier: z.string(),
  created: dateFromSeconds,
  updated: dateFromSeconds,
});

// Type exports
export type BaseApiResponse = z.infer<typeof baseApiResponseSchema>;
export type BaseApiRecord = {
  identifier: string;
  // These should be Date types since they're transformed
  created: Date;
  updated: Date;
};

// Type helper for transformed record
export type TransformedBaseRecord = z.infer<typeof transformedBaseRecordSchema>;

export const detailsSchema = z.record(z.string(), z.unknown()).optional();
export type DetailsType = z.infer<typeof detailsSchema>;

// Base schema for nested records that belong to a parent (e.g. domain->brand)
export const baseNestedRecordSchema = z.object({
  // Common fields for nested records can be added here
});

// Type exports
export type BaseNestedRecord = z.infer<typeof baseNestedRecordSchema>;
