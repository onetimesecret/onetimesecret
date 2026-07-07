// src/schemas/api/internal/responses/colonel-domaintoolbox.ts
//
// Wrapped response schemas for the colonel Domain Toolbox (ticket #43).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import these DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions. Distinct `domaintoolbox` namespace — does NOT touch
// Slice-4's colonel-domains.ts.
//
// The re-verify action REUSES colonelDomainVerifyResponseSchema from
// ./colonel-domains (not redefined here).

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelOrphanedDomainsDetailsSchema,
  colonelDomainProbeRecordSchema,
  colonelDomainProbeDetailsSchema,
  colonelDomainRepairRecordSchema,
  colonelDomainRepairDetailsSchema,
  colonelDomainTransferRecordSchema,
  colonelDomainTransferDetailsSchema,
} from '@/schemas/api/account/responses/colonel-domaintoolbox';
import { z } from 'zod';

// GET /api/colonel/domains/orphaned → ListOrphanedDomains
export const colonelDomainsOrphanedResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelOrphanedDomainsDetailsSchema
);

// GET /api/colonel/domains/:extid/probe → ProbeDomain
export const colonelDomainProbeResponseSchema = createApiResponseSchema(
  colonelDomainProbeRecordSchema,
  colonelDomainProbeDetailsSchema
);

// POST /api/colonel/domains/:extid/repair → RepairDomain
export const colonelDomainRepairResponseSchema = createApiResponseSchema(
  colonelDomainRepairRecordSchema,
  colonelDomainRepairDetailsSchema
);

// POST /api/colonel/domains/:extid/transfer → TransferDomain
export const colonelDomainTransferResponseSchema = createApiResponseSchema(
  colonelDomainTransferRecordSchema,
  colonelDomainTransferDetailsSchema
);

export type ColonelDomainsOrphanedResponse = z.infer<typeof colonelDomainsOrphanedResponseSchema>;
export type ColonelDomainProbeResponse = z.infer<typeof colonelDomainProbeResponseSchema>;
export type ColonelDomainRepairResponse = z.infer<typeof colonelDomainRepairResponseSchema>;
export type ColonelDomainTransferResponse = z.infer<typeof colonelDomainTransferResponseSchema>;
