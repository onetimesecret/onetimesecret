// src/schemas/api/account/requests/update-notification-preference.ts
//
// Request schema for AccountAPI::Logic::Account::UpdateNotificationPreference
// POST /update-notification-preference
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const updateNotificationPreferenceRequestSchema = z.object({
  /** Preference field name (whitelist: notify_on_reveal) */
  field: z.string(),
  /** Boolean string: "true" or "false" */
  value: z.string(),
});

export type UpdateNotificationPreferenceRequest = z.infer<typeof updateNotificationPreferenceRequestSchema>;
