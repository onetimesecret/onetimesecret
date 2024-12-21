import { feedbackInputSchema } from "@/schemas/models";
import { baseRecordSchema } from "@/schemas/models/base";
import { customerSchema } from "@/schemas/models/customer";
import { apiRecordResponseSchema, apiRecordsResponseSchema } from "@/types";
import { z } from "zod";


/**
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDataSchema = baseRecordSchema.extend({
  apitoken: z.string(),
  active: z.string().transform((val) => val === '1'),
  recent_customers: z.array(customerSchema),
  today_feedback: z.array(feedbackInputSchema),
  yesterday_feedback: z.array(feedbackInputSchema),
  older_feedback: z.array(feedbackInputSchema),
  redis_info: z.string().transform(Number),
  plans_enabled: z.string().transform(Number),
  counts: z.object({
    session_count: z.string().transform(Number),
    customer_count: z.string().transform(Number),
    recent_customer_count: z.string().transform(Number),
    metadata_count: z.string().transform(Number),
    secret_count: z.string().transform(Number),
    secrets_created: z.string().transform(Number),
    secrets_shared: z.string().transform(Number),
    emails_sent: z.string().transform(Number),
    feedback_count: z.string().transform(Number),
    today_feedback_count: z.string().transform(Number),
    yesterday_feedback_count: z.string().transform(Number),
    older_feedback_count: z.string().transform(Number),
  }),
});

// Response schemas using the specific record schemas
export const colonelDataResponseSchema = apiRecordResponseSchema(colonelDataSchema);
export const colonelDataRecordsResponseSchema = apiRecordsResponseSchema(colonelDataSchema);
