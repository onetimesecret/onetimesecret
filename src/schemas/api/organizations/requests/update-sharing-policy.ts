// PUT /api/organizations/:extid/sharing-policy
import { sharingPolicySchema } from '@/schemas/contracts/sharing-policy';
import { z } from 'zod';

export const updateSharingPolicyRequestSchema = z.object({
  sharing_policy: sharingPolicySchema,
});
