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
 * `{ record }` ack. `ManageEntitlementOverride` returns only `record`;
 * `createApiResponseSchema` requires `record` and makes only `details`
 * optional, so the absent `details` parses fine.
 */
export const colonelEntitlementOverrideResponseSchema = createApiResponseSchema(
  colonelEntitlementOverrideRecordSchema
);

export type ColonelEntitlementOverrideResponse = z.infer<
  typeof colonelEntitlementOverrideResponseSchema
>;

/**
 * The recomputed MEMBERSHIP entitlement-override state after a grant / revoke
 * / clear (#3907) — the membership-scoped sibling of
 * `colonelEntitlementOverrideRecordSchema`, returned by
 * `ColonelAPI::Logic::Colonel::ManageMembershipEntitlementOverride`:
 *   POST   /api/colonel/organizations/:org_id/members/:member_id/entitlements/grant
 *   POST   /api/colonel/organizations/:org_id/members/:member_id/entitlements/revoke
 *   DELETE /api/colonel/organizations/:org_id/members/:member_id/entitlements/overrides
 *
 * Same shape one scope down: `org_id` and `member_id` are both PUBLIC extids,
 * `entitlement` is null on a full clear, and `effective_entitlements` is the
 * membership's materialised result
 * ((org ∩ role template) + grants - revokes).
 */
export const colonelMembershipEntitlementOverrideRecordSchema = z.object({
  org_id: z.string(),
  member_id: z.string(),
  entitlement: z.string().nullable().optional(),
  action: z.enum(['granted', 'revoked', 'cleared']),
  effective_entitlements: z.array(z.string()),
  grants: z.array(z.string()),
  revokes: z.array(z.string()),
});

export type ColonelMembershipEntitlementOverrideRecord = z.infer<
  typeof colonelMembershipEntitlementOverrideRecordSchema
>;

/**
 * Membership entitlement-override endpoints → `{ record }` ack.
 * `ManageMembershipEntitlementOverride` returns only `record`;
 * `createApiResponseSchema` requires `record` and makes only `details`
 * optional, so the absent `details` parses fine. Registered as
 * `colonelMembershipEntitlementOverride` in `registry.ts`.
 */
export const colonelMembershipEntitlementOverrideResponseSchema = createApiResponseSchema(
  colonelMembershipEntitlementOverrideRecordSchema
);

export type ColonelMembershipEntitlementOverrideResponse = z.infer<
  typeof colonelMembershipEntitlementOverrideResponseSchema
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
 * Membership-cascade counts from an applied reconcile (#3907 item 3):
 * `rematerialize_all_memberships!` totals, surfaced so a partial cascade is
 * operator-visible without log access. `failed_ids` are membership OBJIDs
 * (internal — the identifier `bin/ots memberships doctor` follow-up works in;
 * same posture as the record's `org_id`).
 */
export const colonelReconcileMembershipCascadeSchema = z.object({
  success: z.number(),
  failed: z.number(),
  total: z.number(),
  failed_ids: z.array(z.string()),
});

/**
 * `POST /api/colonel/organizations/:org_id/reconcile` → `{ record }`. MUTATING:
 * re-pulls Stripe and rewrites billing + re-materializes (`stripe_sync`), or
 * re-materializes entitlements from the current plan when there is no
 * subscription (`entitlements_only`). `before`/`after` drive the success diff.
 * `memberships` is null when the run did not cascade (skip statuses) or the
 * cascade raised server-side (logs carry that case).
 */
export const colonelReconcileOrganizationRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  mode: z.enum(['stripe_sync', 'entitlements_only']),
  status: z.string(),
  reason: z.string().nullable(),
  before: colonelReconcileSnapshotSchema,
  // Nullable to match the op's Result contract: `after` is nil on dry runs
  // and Stripe errors. Today the colonel adapter pins dry_run:false and 4xxes
  // Stripe errors before responding, so null never reaches the wire — but the
  // D12 preview work (#3907 item 4) will change that, and a non-nullable
  // schema here would reject those responses with no compile-time signal.
  after: colonelReconcileSnapshotSchema.nullable(),
  memberships: colonelReconcileMembershipCascadeSchema.nullable(),
});

export const colonelReconcileOrganizationResponseSchema = createApiResponseSchema(
  colonelReconcileOrganizationRecordSchema
);

export type ColonelReconcileSnapshot = z.infer<typeof colonelReconcileSnapshotSchema>;
export type ColonelReconcileMembershipCascade = z.infer<
  typeof colonelReconcileMembershipCascadeSchema
>;
export type ColonelReconcileOrganizationRecord = z.infer<
  typeof colonelReconcileOrganizationRecordSchema
>;
export type ColonelReconcileOrganizationResponse = z.infer<
  typeof colonelReconcileOrganizationResponseSchema
>;

/**
 * `POST /api/colonel/organizations/:org_id/transfer-ownership` → `{ record }`
 * ack (#3907 — console peer of `bin/ots org transfer-ownership`). MUTATING:
 * promotes the new owner, pivots the legacy `owner_id` mirror, and demotes
 * every other owner membership. All ids are PUBLIC extids (mirroring
 * `TransferOrganizationOwnership#success_data`, which mirrors the CLI's --json
 * payload). `from_owner_id` is null when the previous `owner_id` pointed at no
 * live customer (`orphaned_owner: true` — the transfer repairs it). `status`
 * is the op's vocabulary verbatim (`success` | `no_change` — failure statuses
 * surface as 4xx form errors, never as a 200).
 */
export const colonelTransferOrganizationOwnershipRecordSchema = z.object({
  org_id: z.string(),
  status: z.string(),
  from_owner_id: z.string().nullable(),
  to_owner_id: z.string(),
  demoted: z.array(z.string()),
  demoted_to: z.string(),
  orphaned_owner: z.boolean(),
});

export const colonelTransferOrganizationOwnershipResponseSchema = createApiResponseSchema(
  colonelTransferOrganizationOwnershipRecordSchema
);

export type ColonelTransferOrganizationOwnershipRecord = z.infer<
  typeof colonelTransferOrganizationOwnershipRecordSchema
>;
export type ColonelTransferOrganizationOwnershipResponse = z.infer<
  typeof colonelTransferOrganizationOwnershipResponseSchema
>;
