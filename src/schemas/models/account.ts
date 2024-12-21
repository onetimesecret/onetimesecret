import { createResponseSchema } from '@/schemas/models/response';
import type Stripe from 'stripe';
import { z } from 'zod';

import { customerSchema } from './customer';

/**
 * Account schema with Stripe integration
 */
export const accountSchema = z.object({
  cust: customerSchema,
  apitoken: z.string().optional(),
  stripe_customer: z.custom<Stripe.Customer>(),
  stripe_subscriptions: z.array(z.custom<Stripe.Subscription>()),
});

export type Account = z.infer<typeof accountSchema>;

// Response schema
export const accountResponseSchema = createResponseSchema(accountSchema, z.object({}));
export type AccountResponse = z.infer<typeof accountResponseSchema>;
