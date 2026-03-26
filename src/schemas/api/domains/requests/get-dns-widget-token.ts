// src/schemas/api/domains/requests/get-dns-widget-token.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDnsWidgetToken
// GET /dns-widget/token
//
//
// GET — no body. Returns DNS widget auth token.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const getDnsWidgetTokenRequestSchema = z.object({});

export type GetDnsWidgetTokenRequest = z.infer<typeof getDnsWidgetTokenRequestSchema>;
