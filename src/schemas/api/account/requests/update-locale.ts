// src/schemas/api/account/requests/update-locale.ts
//
// Request schema for AccountAPI::Logic::Account::UpdateLocale
// POST /update-locale
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const updateLocaleRequestSchema = z.object({
  /** Locale code (e.g. "en", "fr") */
  locale: z.string(),
});

export type UpdateLocaleRequest = z.infer<typeof updateLocaleRequestSchema>;
