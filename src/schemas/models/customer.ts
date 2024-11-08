// src/schemas/models/customer.ts
import { z } from 'zod'
import { baseApiRecordSchema, booleanFromString } from '@/utils/transforms'

export const customerInputSchema = baseApiRecordSchema.extend({
  custid: z.string(),
  role: z.string(),
  planid: z.string().optional(),
  verified: booleanFromString,
  secrets_created: z.number(),
  active: booleanFromString,
  locale: z.string(),
  stripe_checkout_email: z.string().optional(),
  stripe_subscription_id: z.string().optional(),
  stripe_customer_id: z.string().optional(),
  feature_flags: z.record(z.union([
    z.boolean(),
    z.number(),
    z.string()
  ])).optional()
}).passthrough()
