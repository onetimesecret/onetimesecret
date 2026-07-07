// src/schemas/api/internal/responses/colonel-billing.ts
//
// Wrapped response schema for the colonel Billing catalog drift view
// (ticket #45). Internal-only; consumed by the Vue admin console, never
// exposed publicly.
//
// The view imports this DIRECTLY (CONTRACT 3) so it typechecks independently of
// the registry; the Integrate step adds the registry key from wiringInstructions.
// Distinct `billing` namespace — does NOT touch any frozen colonel contract.
//
// READ-ONLY: no mutation/ack schema (spec: read-only drift, sync stays CLI).

import { createApiResponseSchema } from '@/schemas/api/base';
import { colonelBillingCatalogDetailsSchema } from '@/schemas/api/account/responses/colonel-billing';
import { z } from 'zod';

// GET /api/colonel/billing/catalog → GetBillingCatalog
// The record is empty ({}); everything lives under `details`.
export const colonelBillingCatalogResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelBillingCatalogDetailsSchema
);

export type ColonelBillingCatalogResponse = z.infer<typeof colonelBillingCatalogResponseSchema>;
