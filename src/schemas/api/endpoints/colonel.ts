import { createApiResponseSchema } from '@/schemas/api/base';
import { feedbackSchema } from '@/schemas/models';
import { createModelSchema } from '@/schemas/models/base';
import { customerSchema } from '@/schemas/models/customer/index';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDataSchema = createModelSchema({
  apitoken: z.string(),
  active: z.string().transform((val) => val === '1'),
  recent_customers: z.array(customerSchema),
  today_feedback: z.array(feedbackSchema),
  yesterday_feedback: z.array(feedbackSchema),
  older_feedback: z.array(feedbackSchema),
  redis_info: transforms.fromString.number,
  plans_enabled: transforms.fromString.number,
  counts: z.object({
    session_count: transforms.fromString.number,
    customer_count: transforms.fromString.number,
    recent_customer_count: transforms.fromString.number,
    metadata_count: transforms.fromString.number,
    secret_count: transforms.fromString.number,
    secrets_created: transforms.fromString.number,
    secrets_shared: transforms.fromString.number,
    emails_sent: transforms.fromString.number,
    feedback_count: transforms.fromString.number,
    today_feedback_count: transforms.fromString.number,
    yesterday_feedback_count: transforms.fromString.number,
    older_feedback_count: transforms.fromString.number,
  }),
});

// Response schemas using the specific record schemas
export const colonelDataResponseSchema = createApiResponseSchema(colonelDataSchema);

// Export types
export type ColonelData = z.infer<typeof colonelDataSchema>;
