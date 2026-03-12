// src/schemas/api/organizations/requests/list-organizations.ts
//
// Request schema for OrganizationAPI::Logic::Organizations::ListOrganizations
// GET /
//
//
// GET — no params.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const listOrganizationsRequestSchema = z.object({});

export type ListOrganizationsRequest = z.infer<typeof listOrganizationsRequestSchema>;
