// src/schemas/api/internal/responses/colonel-organizations.ts

/**
 * Colonel (Admin) organizations — NEW entitlement-override ack schema (ticket #32).
 *
 * The organizations LIST and the billing-INVESTIGATE read sides already have
 * frozen schemas in `./colonel` (`colonelOrganizationSchema` /
 * `colonelOrganizationsDetailsSchema` and `investigateOrganizationResultSchema`),
 * wrapped in `../../internal/responses/colonel`
 * (`colonelOrganizationsResponseSchema` / `investigateOrganizationResponseSchema`).
 * The organizations screen REUSES those (CONTRACT 3 — reuse over duplication) and
 * does NOT redefine them here.
 *
 * This file adds ONLY the schema for the entitlement-override MUTATION endpoints,
 * which had no frontend contract until this screen surfaced them:
 *   POST   /api/colonel/organizations/:org_id/entitlements/grant
 *   POST   /api/colonel/organizations/:org_id/entitlements/revoke
 *   DELETE /api/colonel/organizations/:org_id/entitlements/overrides
 *
 * It describes the SHAPE `ColonelAPI::Logic::Colonel::ManageEntitlementOverride`
 * returns: the org's PUBLIC id, the affected entitlement (null on a full clear),
 * the past-tense action, and the recomputed override state
 * (effective = plan_entitlements + grants - revokes). Kept in a per-resource file
 * so the organizations screen never edits another screen's contract (CONTRACT 2 /
 * the Zod tripwire — new schemas only).
 */

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

/**
 * The recomputed entitlement-override state after a grant / revoke / clear.
 *
 * `entitlement` is the single entitlement acted on for grant/revoke and is null
 * for a full clear (the endpoint sends `null`, and older acks may omit the key).
 * `action` is the past-tense verb the backend emits (`ACTION_PAST_TENSE`).
 * `effective_entitlements` is the materialised result the org now resolves to.
 */
export const colonelEntitlementOverrideRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  entitlement: z.string().nullable().optional(),
  action: z.enum(['granted', 'revoked', 'cleared']),
  effective_entitlements: z.array(z.string()),
  grants: z.array(z.string()),
  revokes: z.array(z.string()),
});

export type ColonelEntitlementOverrideRecord = z.infer<
  typeof colonelEntitlementOverrideRecordSchema
>;

// Wrapped response schema for the NEW colonel entitlement-override endpoints
// (ticket #32). Internal-only; consumed by the Vue admin bundle. Per-resource
// file so the organizations screen typechecks independently of the shared
// registry (CONTRACT 3) and never touches another screen's contract. The
// Integrate step adds the matching `colonelEntitlementOverride` key to
// `registry.ts`.
//
// The organizations LIST (`colonelOrganizationsResponseSchema`) and the
// billing-INVESTIGATE (`investigateOrganizationResponseSchema`) read schemas are
// REUSED from `./colonel`, not redefined here (CONTRACT 3 — reuse over
// duplication).

/**
 * `POST /api/colonel/organizations/:org_id/entitlements/:action` and
 * `DELETE /api/colonel/organizations/:org_id/entitlements/overrides` →
 * `{ record }` ack. `ManageEntitlementOverride` returns only `record` (no
 * `details`), which `createApiResponseSchema` already makes optional.
 */
export const colonelEntitlementOverrideResponseSchema = createApiResponseSchema(
  colonelEntitlementOverrideRecordSchema
);

export type ColonelEntitlementOverrideResponse = z.infer<
  typeof colonelEntitlementOverrideResponseSchema
>;
