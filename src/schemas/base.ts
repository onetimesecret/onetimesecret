import { z } from 'zod';

/**
 * Core schema definitions and transformers for API boundaries
 */

// Common transformers for API string conversions
export const transforms = {
  fromString: {
    boolean: z.string().transform((val) => val === 'true'),
    number: z.string().transform((val) => Number(val)),
    date: z.string().transform((val) => new Date(Number(val) * 1000)),
  },
} as const;

// Base record schema with timestamps
export const baseRecordSchema = z.object({
  identifier: z.string(),
  created: transforms.fromString.date,
  updated: transforms.fromString.date,
});

// Type for base record after transformation
export type BaseRecord = {
  identifier: string;
  created: Date;
  updated: Date;
};

// API response wrapper
export const apiResponseSchema = <T extends z.ZodType>(recordSchema: T) =>
  z.object({
    success: z.boolean(),
    record: recordSchema,
  });

// Type helper for API responses
export type ApiResponse<T> = {
  success: boolean;
  record: T;
};

// Helper for optional fields
export const optional = <T extends z.ZodType>(schema: T) => schema.optional();

// Helper for arrays of records
export const recordArray = <T extends z.ZodType>(schema: T) => z.array(schema);
