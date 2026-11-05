// src/schemas/api/v3/responses/tokens.ts
//
// V3 JSON wire-format schema for POST /api/v3/token (V3::Logic::Auth::GenerateToken):
// the PASETO v4.public bearer token grant. Timestamps are Unix epoch seconds;
// the token's own claims carry RFC 3339 strings, but the envelope documents
// what a client schedules its refresh from.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

export const bearerTokenSchema = z.object({
  /** The PASETO v4.public token: `v4.public.<payload>.<footer>`. */
  token: z.string().min(1),
  token_type: z.literal('Bearer'),
  /** Lifetime in seconds from issued_at. */
  expires_in: z.number().int().positive(),
  /** Unix epoch seconds. */
  expires_at: z.number().int(),
  /** Unix epoch seconds. */
  issued_at: z.number().int(),
  /** Identifier of the signing key, also carried in the token footer. */
  kid: z.string().min(1),
  /** Granted scopes; `["*"]` is the only grant today. */
  scope: z.array(z.string()),
});

export const bearerTokenDetailsSchema = z.object({
  /** The customer external ID (`ur…`) the token names. */
  subject: z.string(),
  /** The API surface the token is bound to. */
  audience: z.string(),
  /** The issuing deployment (site host). */
  issuer: z.string(),
});

export const bearerTokenResponseSchema = createApiResponseSchema(
  bearerTokenSchema,
  bearerTokenDetailsSchema
);

export type BearerToken = z.infer<typeof bearerTokenSchema>;
export type BearerTokenResponse = z.infer<typeof bearerTokenResponseSchema>;
