// src/schemas/api/organizations/requests/create-organization.ts
//
// Request schema for OrganizationAPI::Logic::Organizations::CreateOrganization
// POST /
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const createOrganizationRequestSchema = z.object({
  /** Organization name (1-100 chars) */
  display_name: z.string(),
  /** Organization description (0-500 chars) */
  description: z.string().optional(),
  /** Contact email (must be unique) */
  contact_email: z.string().optional(),
});

export type CreateOrganizationRequest = z.infer<typeof createOrganizationRequestSchema>;
