// src/schemas/config/billing.ts

/**
 * Billing (optional)
 *
 */

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

const billingSchema = z.object({
  enabled: z.boolean().default(false),
  stripe_key: nullableString,
  webhook_signing_secret: nullableString,
  payment_links: z.object({
    identity: z.object({
      tierid: z.string(),
      month: nullableString,
      year: nullableString,
    }),
    dedicated: z.object({
      tierid: z.string(),
      month: nullableString,
      year: nullableString,
    }),
  }),
});

export { billingSchema };
