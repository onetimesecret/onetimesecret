import { dateSchema } from '@/utils/dates';
import { z } from 'zod';

/**
 * Core schema definitions used across all models
 * Provides base transformation and validation rules
 */

// Base record fields that include timestamps
const baseTimestampFields = {
  created: dateSchema,
  updated: dateSchema,
};

// Base API Response
export const baseApiResponseSchema = z.object({
  success: z.boolean(),
  record: z.object({
    ...baseTimestampFields,
    // Other fields as needed
  }),
});

export const emptyApiRecordSchema = z.object({});

// Base schema for API records
export const baseApiRecordSchema = z.object({
  identifier: z.string(),
  ...baseTimestampFields,
});

// Transformed Base Record - uses same date schema
export const transformedBaseRecordSchema = z.object({
  identifier: z.string(),
  ...baseTimestampFields,
});

// Type exports
export type BaseApiResponse = z.infer<typeof baseApiResponseSchema>;
export type BaseApiRecord = {
  identifier: string;
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
