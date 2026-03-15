// src/schemas/api/v3/responses/csrf.ts
//
// CSRF token validation response. Already JSON-native.

import { z } from 'zod';

export const csrfResponseSchema = z.object({
  isValid: z.boolean(),
  shrimp: z.string(),
});

export type CsrfResponse = z.infer<typeof csrfResponseSchema>;
