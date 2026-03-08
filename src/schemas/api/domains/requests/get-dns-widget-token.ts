// src/schemas/api/domains/requests/get-dns-widget-token.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDnsWidgetToken
// GET /dns-widget/token
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no body. Returns DNS widget auth token.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getDnsWidgetTokenRequestSchema = z.object({});

export type GetDnsWidgetTokenRequest = z.infer<typeof getDnsWidgetTokenRequestSchema>;
