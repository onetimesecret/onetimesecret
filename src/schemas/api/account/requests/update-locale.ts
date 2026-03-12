// src/schemas/api/account/requests/update-locale.ts
//
// Request schema for AccountAPI::Logic::Account::UpdateLocale
// POST /update-locale
//

import { z } from 'zod';

export const updateLocaleRequestSchema = z.object({
  /** Locale code (e.g. "en", "fr") */
  locale: z.string(),
});

export type UpdateLocaleRequest = z.infer<typeof updateLocaleRequestSchema>;
