// src/schemas/models/secret.ts

import { baseApiRecordSchema } from '@/schemas/base'
import { type DetailsType } from '@/schemas/base'
import { booleanFromString, numberFromString } from '@/utils/transforms'
import { z } from 'zod'

// Add state enum
export const SecretState = {
  NEW: 'new',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
} as const

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
  secret_ttl: numberFromString,
  is_truncated: booleanFromString,
  is_burned: booleanFromString,
  is_viewed: booleanFromString,
  has_passphrase: booleanFromString,
})

export const secretListInputSchema = baseApiRecordSchema
  .merge(secretBaseSchema)
  .strip()

// Full secret schema with all fields
export const secretInputSchema = baseApiRecordSchema
  .merge(secretBaseSchema)
  .extend({
    lifespan: numberFromString,
    verification: booleanFromString,
    original_size: numberFromString,
    secret_value: z.string().optional(),
    created_date_utc: z.string(),
    expiration_stamp: z.string(),
    view_path: z.string(),
    burn_path: z.string(),
    secret_url: z.string(),
    burn_url: z.string(),
  })
  .strip()

// Enhanced details schema
export const secretDetailsInputSchema = z.object({
  title: z.string(),
  continue: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean().nullable(),
  is_owner: booleanFromString,
  display_feedback: booleanFromString,
  no_cache: booleanFromString,
  has_passphrase: booleanFromString,
  maxviews: numberFromString,
  view_count: numberFromString,
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
