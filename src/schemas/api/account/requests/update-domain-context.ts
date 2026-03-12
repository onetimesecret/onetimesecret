// src/schemas/api/account/requests/update-domain-context.ts
//
// Request schema for AccountAPI::Logic::Account::UpdateDomainContext
// POST /update-domain-context
//

import { z } from 'zod';

export const updateDomainContextRequestSchema = z.object({
  /** Domain extid to set as active context (or omit to clear) */
  domain_extid: z.string().optional(),
});

export type UpdateDomainContextRequest = z.infer<typeof updateDomainContextRequestSchema>;
