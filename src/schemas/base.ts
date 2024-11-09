import { z } from 'zod';

/**
 * Core schema definitions used across all models
 * Provides base transformation and validation rules
 */

// Base API Response
export const baseApiResponseSchema = z.object({
  success: z.boolean()
});

// Base schema for transforming API records
export const baseApiRecordSchema = z.object({
  identifier: z.string(),
  created: z.string().transform(val => new Date(Number(val) * 1000)),
  updated: z.string().transform(val => new Date(Number(val) * 1000))
});

// Transformed Base Record
export const transformedBaseRecordSchema = z.object({
  identifier: z.string(),
  created: z.date(),
  updated: z.date()
});

// Type exports
export type BaseApiResponse = z.infer<typeof baseApiResponseSchema>;
export type BaseApiRecord = {
  identifier: string;
  created: string;
  updated: string;
};

// Type helper for transformed record
export type TransformedBaseRecord = z.infer<typeof transformedBaseRecordSchema>;

export const detailsSchema = z.record(z.string(), z.unknown()).optional()
export type DetailsType = z.infer<typeof detailsSchema>
