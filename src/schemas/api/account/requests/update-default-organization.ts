// src/schemas/api/account/requests/update-default-organization.ts
//
// Request schema for AccountAPI::Logic::Account::UpdateDefaultOrganization
// POST /update-default-organization
//

import { z } from 'zod';

export const updateDefaultOrganizationRequestSchema = z.object({
  /** Organization objid to make the user's default (the id O-Organization-ID carries) */
  organization_id: z.string().min(1),
});

export type UpdateDefaultOrganizationRequest = z.infer<
  typeof updateDefaultOrganizationRequestSchema
>;
