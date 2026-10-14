// src/schemas/api/v3/requests/content/base.ts

import { secretDisplayTypeSchema } from '@/schemas/contracts/secret';
import { z } from 'zod';

export const baseSecretPayloadSchema = z.object({
  kind: z.enum(['generate', 'conceal', 'share']),
  share_domain: z.string(),
  recipient: z.string().optional(),
  passphrase: z.string().optional(),
  ttl: z
    .union([z.string().regex(/^\d+$/).transform(Number), z.number().int()])
    .optional(),
  /**
   * How the recipient's client should present the value. Omitted means
   * plain text. Honored on conceal only; the generate endpoint ignores it
   * (a generated password is always text).
   */
  display_type: secretDisplayTypeSchema.optional(),
});
