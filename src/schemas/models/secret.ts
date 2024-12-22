import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/utils/transforms';
import { z } from 'zod';

/**
 * @fileoverview Secret schema with standardized transformations
 *
 * Key improvements:
 * 1. Consistent use of transforms for type conversion
 * 2. Standardized response schema pattern
 * 3. Clear type boundaries
 */

export const SecretState = {
  NEW: 'new',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
} as const;

export type SecretState = (typeof SecretState)[keyof typeof SecretState];

// Create reusable schema for the state
export const secretStateSchema = z.enum(Object.values(SecretState) as [string, ...string[]]);

// Base schema for core fields
const secretBaseSchema = z.object({
  key: z.string(),
  shortkey: z.string(),
  state: secretStateSchema,
  is_truncated: transforms.fromString.boolean,
  has_passphrase: transforms.fromString.boolean,
  verification: transforms.fromString.boolean,
  secret_value: z.string().optional(),
});

// List view schema (stripped down version)
export const secretListSchema = createModelSchema(secretBaseSchema.shape).strip();

// Full secret schema with all fields
export const secretSchema = createModelSchema({
  ...secretBaseSchema.shape,
  secret_ttl: transforms.fromString.number.nullable(),
  lifespan: transforms.fromString.ttlToNaturalLanguage,
  original_size: z.string(),
}).strip();

// Details schema with explicit typing
export const secretDetailsSchema = z.object({
  continue: transforms.fromString.boolean,
  is_owner: transforms.fromString.boolean,
  show_secret: transforms.fromString.boolean,
  correct_passphrase: transforms.fromString.boolean,
  display_lines: transforms.fromString.number,
  one_liner: transforms.fromString.boolean.nullable(),
});

// Export types
export type Secret = z.infer<typeof secretSchema>;
export type SecretDetails = z.infer<typeof secretDetailsSchema>;
export type SecretList = z.infer<typeof secretListSchema>;
