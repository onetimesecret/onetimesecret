// ReceiveFeedback acknowledges submission; it does not return the stored entity.
import { z } from 'zod';

export const feedbackResponseSchema = z.strictObject({
  record: z.strictObject({}),
  details: z.strictObject({ message: z.string() }),
});

export type FeedbackResponse = z.infer<typeof feedbackResponseSchema>;
