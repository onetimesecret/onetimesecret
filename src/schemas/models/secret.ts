// src/schemas/models/secret.ts

import { baseApiRecordSchema } from '@/schemas/base'
import { type DetailsType } from '@/schemas/base'
import { booleanFromString } from '@/utils/transforms'
import { z } from 'zod'

// Add state enum
export const SecretState = {
  NEW: 'new',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
} as const

// Base schema for core fields
// Base schema for core fields
const secretBaseSchema = z.object({
  key: z.string(),
  shortkey: z.string(),
  state: z.enum([
    SecretState.NEW,
    SecretState.RECEIVED,
    SecretState.BURNED,
    SecretState.VIEWED
  ]),
  is_truncated: booleanFromString,
  has_passphrase: booleanFromString,
  verification: booleanFromString,
})

export const secretListInputSchema = baseApiRecordSchema
  .merge(secretBaseSchema)
  .strip()

// Full secret schema with all fields
export const secretInputSchema = baseApiRecordSchema
  .merge(secretBaseSchema)
  .extend({
    secret_ttl: z.number().nullable(),
    lifespan: z.string(),
    original_size: z.string(),
  })
  .strip()

// Enhanced details schema
export const secretDetailsInputSchema = z.object({
  continue: z.boolean(),
  is_owner: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean().nullable(),
})


// Export types
export type Secret = z.infer<typeof secretInputSchema>
export type SecretDetails = z.infer<typeof secretDetailsInputSchema> & DetailsType
export type SecretList = z.infer<typeof secretListInputSchema>

// Response schemas
export const secretResponseSchema = z.object({
  success: z.boolean(),
  record: secretInputSchema,
  details: secretDetailsInputSchema
})

export type SecretResponse = z.infer<typeof secretResponseSchema>
