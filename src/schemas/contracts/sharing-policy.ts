import { z } from 'zod';

export const sharingPolicySchema = z.strictObject({
  recipient_email_mode: z.enum(['unrestricted', 'restricted', 'disabled']),
  recipient_email_domains: z.array(z.string().min(1)),
  passphrase_required: z.boolean(),
  max_ttl: z.int().min(60).nullable(),
});

export type SharingPolicy = z.infer<typeof sharingPolicySchema>;
