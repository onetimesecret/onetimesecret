// src/schemas/api/account/responses/colonel-organizations.ts

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
