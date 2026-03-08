// src/schemas/api/account/requests/update-password.ts
//
// Request schema for AccountAPI::Logic::Account::UpdatePassword
// POST /change-password
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// Field name "password-confirm" has a hyphen — needs bracket notation.

import { z } from 'zod';

export const updatePasswordRequestSchema = z.object({
  /** Current password */
  password: z.string(),
  /** New password (min 6 chars) */
  newpassword: z.string(),
  /** New password confirmation (must match) */
  'password-confirm': z.string(),
});

export type UpdatePasswordRequest = z.infer<typeof updatePasswordRequestSchema>;
