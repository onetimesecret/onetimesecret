// src/schemas/api/colonel/requests/list-custom-domains.ts
//
// Request schema for ColonelAPI::Logic::Colonel::ListCustomDomains
// GET /domains
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — pagination same as ListUsers.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const listCustomDomainsRequestSchema = z.object({});

export type ListCustomDomainsRequest = z.infer<typeof listCustomDomainsRequestSchema>;
