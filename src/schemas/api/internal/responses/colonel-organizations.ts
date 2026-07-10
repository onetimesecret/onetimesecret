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
import { transforms } from '@/schemas/transforms';
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

// ============================================================================
// Organization DETAIL + reconcile schemas (colonel org audit remediation)
//
// The Organizations screen gained a first-class detail page. These describe the
// two NEW endpoints that page consumes:
//   GET  /api/colonel/organizations/:org_id            → colonelOrganizationDetail
//   POST /api/colonel/organizations/:org_id/reconcile  → reconcile ack
//
// Shapes mirror the VALIDATED live output of
// `ColonelAPI::Logic::Colonel::GetOrganizationDetail` /
// `ReconcileOrganization`. Timestamps arrive as epoch ints and are transformed
// to Date (matching the sibling colonel detail schemas). `null` where the
// backend can emit null; `display_name` stays nullable to agree with the LIST
// schema (`colonelOrganizationSchema`), which is corroborating evidence.
// ============================================================================

/**
 * The materialised entitlement breakdown for one org. The operator reads this
 * on load (no blind mutation): `materialized` = the effective set the org
 * resolves to = `expected` = (plan ∪ grants) − revokes. `drift` flags any
 * mismatch between materialized and expected (normally empty / in_sync).
 * `plan_stale` true = plan definition changed since last materialization
 * (offer reconcile); null = the plan could not be loaded.
 */
export const colonelOrganizationDetailEntitlementsSchema = z.object({
  plan: z.array(z.string()),
  grants: z.array(z.string()),
  revokes: z.array(z.string()),
  materialized: z.array(z.string()),
  expected: z.array(z.string()),
  materialized_flag: z.boolean(),
  materialized_at: transforms.fromNumber.toDateNullable,
  plan_stale: z.boolean().nullable(),
  drift: z.object({
    extra: z.array(z.string()),
    missing: z.array(z.string()),
    in_sync: z.boolean(),
  }),
});

/** One organization member row on the detail page. */
export const colonelOrganizationDetailMemberSchema = z.object({
  extid: z.string(),
  email: z.string().nullable(),
  role: z.string().nullable(),
  status: z.string().nullable(),
  is_owner: z.boolean(),
  joined_at: transforms.fromNumber.toDateNullable,
  created: transforms.fromNumber.toDateNullable,
});

/** One organization domain row on the detail page. */
export const colonelOrganizationDetailDomainSchema = z.object({
  extid: z.string(),
  domain_id: z.string(),
  display_domain: z.string(),
  base_domain: z.string(),
  status: z.string().nullable(),
  verified: z.boolean(),
  resolving: z.boolean(),
  verification_state: z.string(),
  ready: z.boolean(),
  created: transforms.fromNumber.toDateNullable,
});

/** The organization record on the detail page (billing read-out + lifecycle). */
export const colonelOrganizationDetailRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  display_name: z.string().nullable(),
  description: z.string().nullable(),
  is_default: z.boolean(),
  archived: z.boolean(),
  archived_at: transforms.fromNumber.toDateNullable,
  archived_comment: z.string().nullable(),
  contact_email: z.string().nullable(),
  owner_id: z.string(),
  owner_email: z.string().nullable(),
  billing_email: z.string().nullable(),
  member_count: z.number(),
  domain_count: z.number(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDateNullable,
  planid: z.string().nullable(),
  stripe_customer_id: z.string().nullable(),
  stripe_subscription_id: z.string().nullable(),
  subscription_status: z.string().nullable(),
  subscription_period_end: z.string().nullable(),
  billing_email_present: z.boolean(),
  sync_status: z.string(),
  sync_status_reason: z.string().nullable(),
});

/** The `details` envelope: entitlement breakdown + members + domains. */
export const colonelOrganizationDetailDetailsSchema = z.object({
  entitlements: colonelOrganizationDetailEntitlementsSchema,
  members: z.array(colonelOrganizationDetailMemberSchema),
  domains: z.array(colonelOrganizationDetailDomainSchema),
});

/**
 * `GET /api/colonel/organizations/:org_id` → `{ record, details }`. `:org_id`
 * is the org's PUBLIC id (extid).
 */
export const colonelOrganizationDetailResponseSchema = createApiResponseSchema(
  colonelOrganizationDetailRecordSchema,
  colonelOrganizationDetailDetailsSchema
);

export type ColonelOrganizationDetailEntitlements = z.infer<
  typeof colonelOrganizationDetailEntitlementsSchema
>;
export type ColonelOrganizationDetailMember = z.infer<typeof colonelOrganizationDetailMemberSchema>;
export type ColonelOrganizationDetailDomain = z.infer<typeof colonelOrganizationDetailDomainSchema>;
export type ColonelOrganizationDetailRecord = z.infer<typeof colonelOrganizationDetailRecordSchema>;
export type ColonelOrganizationDetailResponse = z.infer<
  typeof colonelOrganizationDetailResponseSchema
>;

/**
 * Billing snapshot on either side of a reconcile. `materialized_count` is the
 * size of the effective entitlement set; the plan/subscription fields mirror
 * the (nullable) record fields.
 */
export const colonelReconcileSnapshotSchema = z.object({
  planid: z.string().nullable(),
  subscription_status: z.string().nullable(),
  subscription_period_end: z.string().nullable(),
  materialized_count: z.number(),
});

/**
 * `POST /api/colonel/organizations/:org_id/reconcile` → `{ record }`. MUTATING:
 * re-pulls Stripe and rewrites billing + re-materializes (`stripe_sync`), or
 * re-materializes entitlements from the current plan when there is no
 * subscription (`entitlements_only`). `before`/`after` drive the success diff.
 */
export const colonelReconcileOrganizationRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  mode: z.enum(['stripe_sync', 'entitlements_only']),
  status: z.string(),
  reason: z.string().nullable(),
  before: colonelReconcileSnapshotSchema,
  after: colonelReconcileSnapshotSchema,
});

export const colonelReconcileOrganizationResponseSchema = createApiResponseSchema(
  colonelReconcileOrganizationRecordSchema
);

export type ColonelReconcileSnapshot = z.infer<typeof colonelReconcileSnapshotSchema>;
export type ColonelReconcileOrganizationRecord = z.infer<
  typeof colonelReconcileOrganizationRecordSchema
>;
export type ColonelReconcileOrganizationResponse = z.infer<
  typeof colonelReconcileOrganizationResponseSchema
>;
