// src/schemas/api/organizations/requests/delete-organization.ts
//
// Request schema for OrganizationAPI::Logic::Organizations::DeleteOrganization
// DELETE /:extid
//
//
// DELETE — extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const deleteOrganizationRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Organizations::DeleteOrganization raise_concerns / process
});

export type DeleteOrganizationRequest = z.infer<typeof deleteOrganizationRequestSchema>;
