// src/schemas/api/domains/responses/test-email-config.ts
//
// Response schema for POST /api/domains/:domain_extid/email-config/test

import { z } from 'zod';

/**
 * Details returned by the test email endpoint.
 *
 * On success: delivery metadata (sent_to, from_address, etc.)
 * On failure: error_code + human-readable description.
 */
export const testEmailConfigDetailsSchema = z.object({
  sent_to: z.string().optional(),
  from_address: z.string().optional(),
  from_name: z.string().nullable().optional(),
  provider: z.string().optional(),
  sent_at: z.string().optional(),
  error_code: z.string().optional(),
  description: z.string().optional(),
});

/**
 * Response schema for POST /api/domains/:domain_extid/email-config/test
 *
 * A simple success/message envelope — does not use `createApiResponseSchema`
 * because the backend returns a flat object, not a `record`-wrapped envelope.
 */
export const testEmailConfigResponseSchema = z.object({
  user_id: z.string(),
  success: z.boolean(),
  message: z.string(),
  details: testEmailConfigDetailsSchema,
});

export type TestEmailConfigResponse = z.infer<typeof testEmailConfigResponseSchema>;
