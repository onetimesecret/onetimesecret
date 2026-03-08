// src/schemas/api/organizations/requests/update-organization.ts
//
// Request schema for OrganizationAPI::Logic::Organizations::UpdateOrganization
// PUT /:extid
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const updateOrganizationRequestSchema = z.object({
  /** Organization name (1-100 chars) */
  display_name: z.string().optional(),
  /** Organization description (0-500 chars) */
  description: z.string().optional(),
  /** Contact email */
  contact_email: z.string().optional(),
});

export type UpdateOrganizationRequest = z.infer<typeof updateOrganizationRequestSchema>;
