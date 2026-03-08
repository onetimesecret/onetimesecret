// src/schemas/api/organizations/requests/get-organization.ts
//
// Request schema for OrganizationAPI::Logic::Organizations::GetOrganization
// GET /:extid
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const getOrganizationRequestSchema = z.object({
  // TODO: fill in from OrganizationAPI::Logic::Organizations::GetOrganization raise_concerns / process
});

export type GetOrganizationRequest = z.infer<typeof getOrganizationRequestSchema>;
