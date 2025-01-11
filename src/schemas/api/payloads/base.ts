// src/schemas/api/payloads/base.ts

import { z } from 'zod';

export const baseSecretPayloadSchema = z.object({
  kind: z.enum(['generate', 'conceal', 'share']),
  share_domain: z.string(),
  recipient: z.string().optional(),
  passphrase: z.string().optional(),
  ttl: z
    .union([z.string().regex(/^\d+$/).transform(Number), z.number().int()])
    .optional(),
});
