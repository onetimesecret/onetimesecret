import { createRecordResponseSchema, createRecordsResponseSchema } from "@/schemas/api/base";
import { feedbackInputSchema } from "@/schemas/models";
import { createModelSchema } from "@/schemas/models/base";
import { customerSchema } from "@/schemas/models/customer";
import { transforms } from "@/utils/transforms";
import { z } from "zod";


/**
 * Raw API data structures before transformation
 * These represent the API shape that will be transformed by input schemas
 */
export const colonelDataSchema = createModelSchema({
  apitoken: z.string(),
  active: z.string().transform((val) => val === '1'),
  recent_customers: z.array(customerSchema),
  today_feedback: z.array(feedbackInputSchema),
  yesterday_feedback: z.array(feedbackInputSchema),
  older_feedback: z.array(feedbackInputSchema),
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
export const colonelDataResponseSchema = createRecordResponseSchema(colonelDataSchema);
export const colonelDataRecordsResponseSchema = createRecordsResponseSchema(colonelDataSchema);
