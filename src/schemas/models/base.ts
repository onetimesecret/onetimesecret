import { transforms } from '@/utils/transforms';
import { z } from 'zod';

/**
 * Base Model Schema
 * Maps to Ruby's base model class and defines common model attributes
 */
export const baseModelSchema = z.object({
  identifier: z.string(),
  created: transforms.fromString.date,
  updated: transforms.fromString.date,
});

// Type helper for base model fields
export type BaseModel = z.infer<typeof baseModelSchema>;

// Helper to extend base model schema
export const createModelSchema = <T extends z.ZodType>(
  fields: T
) => baseModelSchema.extend(fields.shape);

/**
 * Base schema for all API records
 * Matches BaseApiRecord interface and handles identifier pattern
 *
 * Ruby models use different identifier patterns:
 * - Direct field (e.g. Customer.custid)
 * - Generated (e.g. Secret.generate_id)
 * - Derived (e.g. CustomDomain.derive_id)
 * - Composite (e.g. RateLimit.[fields].sha256)
 *
 * We standardize this in the schema layer by:
 * 1. Always including the identifier field from API
 * 2. Allowing models to specify their identifier source
 * 3. Transforming as needed in model-specific schemas
 */

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
