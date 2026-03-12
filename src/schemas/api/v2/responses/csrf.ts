// src/schemas/api/v2/responses/csrf.ts
//
// Response schema for CSRF token validation.

import { z } from 'zod';

export const csrfResponseSchema = z.object({
  isValid: z.boolean(),
  shrimp: z.string(),
});

export type CsrfResponse = z.infer<typeof csrfResponseSchema>;
