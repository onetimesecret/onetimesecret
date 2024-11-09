// src/schemas/models/secret.ts

import { baseApiRecordSchema } from '@/schemas/base'
import { booleanFromString } from '@/utils/transforms'
import { z } from 'zod'

/**
 * Schema for secret record from API
 * Handles string -> boolean coercion and optional fields
 */
export const secretInputSchema = baseApiRecordSchema.extend({
  // Core fields
  key: z.string(),
  secret_key: z.string(),
  is_truncated: booleanFromString,
  original_size: z.number(),
  verification: z.string(),
  share_domain: z.string(),
  is_owner: booleanFromString,
  has_passphrase: booleanFromString,

  // Only present after reveal
  secret_value: z.string().optional(),
})

/**
 * Schema for secret details/state
 */
export const secretDetailsSchema = z.object({
  continue: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean()
})

export type SecretData = z.infer<typeof secretInputSchema>
export type SecretDetails = z.infer<typeof secretDetailsSchema>

/**
 * Combined schema for API responses
 */
export const secretResponseSchema = z.object({
  success: z.boolean(),
  record: secretInputSchema,
  details: secretDetailsSchema
})

export type SecretResponse = z.infer<typeof secretResponseSchema>
