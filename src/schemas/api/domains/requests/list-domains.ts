// src/schemas/api/domains/requests/list-domains.ts
//
// Request schema for DomainsAPI::Logic::Domains::ListDomains
// GET /
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no params.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const listDomainsRequestSchema = z.object({});

export type ListDomainsRequest = z.infer<typeof listDomainsRequestSchema>;
