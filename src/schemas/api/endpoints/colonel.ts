import { feedbackSchema } from '@/schemas/models';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * An abridged customer record used in the recent list.
 */
export const recentCustomerSchema = z.object({
  custid: z.string(), // Not always an email address (e.g. GLOBAL for new installs)
  planid: z.string(),
  colonel: z.boolean(),
  secrets_created: transforms.fromString.number,
  secrets_shared: transforms.fromString.number,
  emails_sent: transforms.fromString.number,
  verified: z.boolean(),
  stamp: z.string(),
});

/**
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDetailsSchema = z.object({
  recent_customers: z.array(recentCustomerSchema),
  today_feedback: z.array(feedbackSchema),
  yesterday_feedback: z.array(feedbackSchema),
  older_feedback: z.array(feedbackSchema).nullable(),
  redis_info: z.string(),
  plans_enabled: z.boolean(),
  counts: z.object({
    customer_count: transforms.fromString.number,
    emails_sent: transforms.fromString.number,
    feedback_count: transforms.fromString.number,
    metadata_count: transforms.fromString.number,
    older_feedback_count: transforms.fromString.number,
    recent_customer_count: transforms.fromString.number,
    secret_count: transforms.fromString.number,
    secrets_created: transforms.fromString.number,
    secrets_shared: transforms.fromString.number,
    session_count: transforms.fromString.number,
    today_feedback_count: transforms.fromString.number,
    yesterday_feedback_count: transforms.fromString.number,
  }),
});

// Export types
export type ColonelDetails = z.infer<typeof colonelDetailsSchema>;
export type RecentCustomer = z.infer<typeof recentCustomerSchema>;
