import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

/**
 * Base Model Schema
 * Maps to Ruby's base model class and defines common model attributes
 *
 * Design Decisions:
 *
 * 1. Common Fields:
 *    All models share:
 *    - identifier: unique ID
 *    - created/updated: timestamps
 *    These match Ruby model conventions
 *
 * 2. Model Creation Pattern:
 *    - createModelSchema helper enforces consistent model structure
 *    - Ensures all models extend base fields
 *    - Maintains type safety with Ruby models
 *
 * 3. Type Conversion:
 *    - Handles Redis string -> proper type conversion
 *    - Uses consistent transform patterns
 *    - Maintains type safety across boundaries
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
 *   email: z.email()
 * })
 * ```
 *
 * This matches Zod's own API design (e.g., z.object()) and provides more
 * flexibility while reducing boilerplate. For reusable schemas, you can
 * still create named constants from the result (i.e. `userSchema`)
 */
export const createModelSchema = <T extends z.ZodRawShape>(fields: T) =>
  baseModelSchema.extend(fields);
