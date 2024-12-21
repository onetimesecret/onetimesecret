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

/**
 * Helper to extend base model schema
 * Takes a ZodRawShape following Zod's builder pattern conventions:
 *
 * Example:
 * ```
 * export const userSchema = createModelSchema({
 *   name: z.string(),
 *   email: z.string().email()
 * })
 * ```
 *
 * This matches Zod's own API design (e.g., z.object()) and provides more
 * flexibility while reducing boilerplate. For reusable schemas, you can
 * still create named constants from the result (i.e. `userSchema`)
 *
 */
export const createModelSchema = <T extends z.ZodRawShape>(fields: T) =>
  baseModelSchema.extend(fields);

// Helper for optional fields
export const optional = <T extends z.ZodType>(schema: T) => schema.optional();

// Helper for arrays of records
export const recordArray = <T extends z.ZodType>(schema: T) => z.array(schema);
