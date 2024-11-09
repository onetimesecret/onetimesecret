// src/schemas/models/index.ts
export * from './customer.ts'
export * from './brand.ts'
export * from './domain.ts'

import { baseApiRecordSchema } from '@/schemas/base.ts';
import { z } from 'zod'

/**
 * Input schema for feedback messages from API
 * Handles basic feedback data with message and timestamp
 */
const feedbackBaseSchema = z.object({
  // Feedback content
  msg: z.string().min(1),

  // Creation timestamp
  created: z.string().datetime()
})

// Combine base record schema with feedback-specific fields
export const feedbackInputSchema = baseApiRecordSchema.merge(feedbackBaseSchema)

// Export inferred type for use in stores/components
export type Feedback = z.infer<typeof feedbackInputSchema>
