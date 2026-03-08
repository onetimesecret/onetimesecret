// src/schemas/api/account/requests/request-email-change.ts
//
// Request schema for AccountAPI::Logic::Account::RequestEmailChange
// POST /change-email
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const requestEmailChangeRequestSchema = z.object({
  /** New email address */
  newemail: z.string(),
});

export type RequestEmailChangeRequest = z.infer<typeof requestEmailChangeRequestSchema>;
