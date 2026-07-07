// src/schemas/api/internal/responses/colonel-domains.ts
//
// Wrapped response schema for the NEW colonel domain-verify endpoint (ticket
// #31). Internal-only; consumed by the Vue admin bundle. Per-resource file so
// the domains screen typechecks independently of the shared registry (CONTRACT
// 3) and never touches another screen's contract. The Integrate step adds the
// matching `colonelDomainVerify` key to `registry.ts`.
//
// The domains LIST read schema (`colonelCustomDomainsResponseSchema`) is REUSED
// from `./colonel`, not redefined here.

import {
  colonelDomainVerifyRecordSchema,
  colonelDomainVerifyDetailsSchema,
} from '@/schemas/api/account/responses/colonel-domains';
import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

/** `POST /api/colonel/domains/:extid/verify` → `{ record, details }` ack. */
export const colonelDomainVerifyResponseSchema = createApiResponseSchema(
  colonelDomainVerifyRecordSchema,
  colonelDomainVerifyDetailsSchema
);

export type ColonelDomainVerifyResponse = z.infer<typeof colonelDomainVerifyResponseSchema>;
