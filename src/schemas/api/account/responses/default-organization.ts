// src/schemas/api/account/responses/default-organization.ts
//
// Response schema for AccountAPI::Logic::Account::UpdateDefaultOrganization
// POST /api/account/update-default-organization
//

import { z } from 'zod';

/**
 * The server sets the user's default organization and also selects it for the
 * current session. Both ids are objids. The previous default is the org that
 * was the user's default before the change (their chosen one, else the
 * default workspace they own); null when there was none.
 */
export const updateDefaultOrganizationResponseSchema = z.object({
  organization_id: z.string(),
  previous_default_organization_id: z.string().nullish(),
});

export type UpdateDefaultOrganizationResponse = z.infer<
  typeof updateDefaultOrganizationResponseSchema
>;
