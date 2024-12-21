import { baseRecordSchema } from "@/schemas/models/base";
import { z } from "zod";

/**
 * Input schema for feedback messages from API
 * Handles basic feedback data with message and timestamp
 */
export const feedbackBaseSchema = z.object({
  // Feedback content
  msg: z.string().min(1),

  // Creation timestamp
  created: z.string().datetime()
})

// Combine base record schema with feedback-specific fields
export const feedbackInputSchema = baseRecordSchema.merge(feedbackBaseSchema)

// Export inferred type for use in stores/components
export type Feedback = z.infer<typeof feedbackInputSchema>
