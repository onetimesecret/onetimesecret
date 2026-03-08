// src/schemas/api/account/requests/update-domain-context.ts
//
// Request schema for AccountAPI::Logic::Account::UpdateDomainContext
// POST /update-domain-context
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const updateDomainContextRequestSchema = z.object({
  /** Domain extid to set as active context (or omit to clear) */
  domain_extid: z.string().optional(),
});

export type UpdateDomainContextRequest = z.infer<typeof updateDomainContextRequestSchema>;
